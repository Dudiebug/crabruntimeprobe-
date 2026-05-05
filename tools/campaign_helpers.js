const fs = require('fs');
const path = require('path');

const CAMPAIGN = 'crabruntimeprobe-read-map';
const PLAN_PATH = path.join('campaign', 'campaign_plan.crabruntimeprobe-read-map.json');
const STATE_PATH = path.join('evidence', 'campaign_state.json');
const DOC_PATH = path.join('docs', 'CAMPAIGN_STATUS.md');

const ALL_GATES = [
  'allowHudTickHook',
  'allowUnknownRoleProbes',
  'allowJoinedClientDeepProbes',
  'allowDeepArrayProbes',
  'allowInventoryInfoProbes',
  'allowHealthProbes',
  'allowWriteProbes',
  'allowRpcProbes'
];

const ALWAYS_FORBIDDEN = [
  'allowHudTickHook',
  'allowWriteProbes',
  'allowRpcProbes'
];

function nowIso() {
  return new Date().toISOString();
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function readJsonIfExists(file) {
  if (!fs.existsSync(file)) return null;
  return readJson(file);
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(data, null, 2)}\n`);
}

function walk(dir, filter) {
  if (!fs.existsSync(dir)) return [];
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, filter));
    else if (!filter || filter(entry.name, full)) out.push(full);
  }
  return out;
}

function readTextIfExists(file) {
  return fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
}

function readJsonl(file) {
  return readTextIfExists(file)
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return null;
      }
    })
    .filter(Boolean);
}

function parseKeyValueText(text) {
  const out = {};
  for (const line of text.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match) out[match[1]] = match[2];
  }
  return out;
}

function loadPlan(repoRoot = process.cwd()) {
  const plan = readJson(path.join(repoRoot, PLAN_PATH));
  if (plan.campaign !== CAMPAIGN) {
    throw new Error(`Unexpected campaign name: ${plan.campaign}`);
  }
  if (!Array.isArray(plan.phases) || plan.phases.length === 0) {
    throw new Error('Campaign plan has no phases.');
  }
  return plan;
}

function gateConfigForPhase(phase) {
  const gates = {};
  for (const gate of ALL_GATES) gates[gate] = false;
  for (const [gate, value] of Object.entries(phase.requiredGates || {})) {
    gates[gate] = value === true;
  }
  validatePhaseSafety(phase, gates);
  return gates;
}

function validatePhaseSafety(phase, gates = gateConfigForPhaseUnchecked(phase)) {
  for (const gate of ALWAYS_FORBIDDEN) {
    if (gates[gate] === true || (phase.requiredGates || {})[gate] === true) {
      throw new Error(`${phase.phaseId} may not enable ${gate}.`);
    }
  }
  if (gates.allowHealthProbes && !/^health-|^multiplayer-health-/.test(phase.phaseId)) {
    throw new Error(`${phase.phaseId} may not enable allowHealthProbes.`);
  }
  if (gates.allowInventoryInfoProbes && phase.phaseId !== 'inventoryinfo-scalar-read') {
    throw new Error(`${phase.phaseId} may not enable allowInventoryInfoProbes.`);
  }
  if (gates.allowDeepArrayProbes && !/deep|inventory-element-da-read/.test(phase.phaseId)) {
    throw new Error(`${phase.phaseId} may not enable allowDeepArrayProbes.`);
  }
  for (const gate of phase.forbiddenGates || []) {
    if (gates[gate] === true) {
      throw new Error(`${phase.phaseId} forbidden gate enabled: ${gate}.`);
    }
  }
  return true;
}

function gateConfigForPhaseUnchecked(phase) {
  const gates = {};
  for (const gate of ALL_GATES) gates[gate] = false;
  for (const [gate, value] of Object.entries(phase.requiredGates || {})) {
    gates[gate] = value === true;
  }
  return gates;
}

function evidenceFacts(repoRoot = process.cwd()) {
  const evidenceRoot = path.join(repoRoot, 'evidence', 'runtime');
  const probeFiles = walk(evidenceRoot, (name) => name === 'probe_results.jsonl');
  const accessFiles = walk(evidenceRoot, (name) => name === 'access_evidence.jsonl');
  const manifestFiles = walk(evidenceRoot, (name) => name === 'session_manifest.json');
  const summaryFiles = walk(evidenceRoot, (name) => name === 'diagnostic_summary.txt');
  const rows = [...probeFiles, ...accessFiles].flatMap(readJsonl);
  const manifests = manifestFiles.map((file) => ({ file, data: readJsonIfExists(file) })).filter((x) => x.data);
  const summaries = summaryFiles.map((file) => ({ file, values: parseKeyValueText(readTextIfExists(file)) }));
  const text = [
    ...rows.map((row) => JSON.stringify(row)),
    ...manifests.map((row) => JSON.stringify(row.data)),
    ...summaries.map((row) => Object.entries(row.values).map(([k, v]) => `${k}=${v}`).join('\n'))
  ].join('\n');
  const latestManifest = manifests
    .slice()
    .sort((a, b) => String(a.data.sessionId || '').localeCompare(String(b.data.sessionId || '')))
    .pop();
  const latestSummary = summaries
    .slice()
    .sort((a, b) => a.file.localeCompare(b.file))
    .pop();
  return {
    rows,
    manifests,
    summaries,
    text,
    latestSessionId: latestManifest ? latestManifest.data.sessionId || null : null,
    latestCommit: latestManifest && latestManifest.data.buildInfo ? latestManifest.data.buildInfo.git_commit || null : null,
    latestSummaryPath: latestSummary ? path.relative(repoRoot, latestSummary.file).replace(/\\/g, '/') : null
  };
}

function hasProbe(rows, names) {
  const wanted = new Set(names);
  return rows.some((row) => wanted.has(row.event) || wanted.has(row.probeName) || wanted.has(row.probeId));
}

function seedCompletionsFromEvidence(plan, repoRoot = process.cwd()) {
  const facts = evidenceFacts(repoRoot);
  const completed = [];
  const add = (phaseId, reason) => {
    if (plan.phases.some((phase) => phase.phaseId === phaseId)) {
      completed.push({
        phaseId,
        status: 'complete',
        completedAt: nowIso(),
        source: 'imported-evidence',
        reason,
        latestSessionId: facts.latestSessionId || '',
        latestCommit: facts.latestCommit || '',
        latestSummaryPath: facts.latestSummaryPath || ''
      });
    }
  };

  if (/Debug\.StartupSmoke|startup_smoke_appeared\s*=\s*True/i.test(facts.text)) {
    add('smoke-startup', 'Imported evidence contains startup smoke.');
  }
  if (/tickDriver["=:]\s*"?executeDelay|tick_source_registered\s*=\s*executeDelay/i.test(facts.text)) {
    add('executeDelay', 'Imported evidence contains executeDelay runtime proof.');
  }
  if (/Observe\.Context|observe_context_appeared\s*=\s*True|observe_context_count\s*=\s*[1-9]/i.test(facts.text)) {
    add('observe-context', 'Imported evidence contains Observe.Context rows.');
  }
  if (hasProbe(facts.rows, [
    'CrabPS.GetPropertyValue.WeaponDA',
    'CrabPS.GetPropertyValue.AbilityDA',
    'CrabPS.GetPropertyValue.MeleeDA'
  ])) {
    add('equipment-property-read', 'Imported evidence contains equipment property probes.');
  }
  if (hasProbe(facts.rows, [
    'CrabPS.GetPropertyValue.HealthInfo',
    'CrabPS.HealthInfo.CurrentHealth',
    'CrabPS.HealthInfo.CurrentMaxHealth',
    'CrabPS.GetPropertyValue.BaseMaxHealth',
    'CrabPS.GetPropertyValue.MaxHealthMultiplier'
  ])) {
    add('health-playerstate-read', 'Imported evidence contains PlayerState health scalar probes.');
  }
  if (hasProbe(facts.rows, ['Health.PlayerState.Sample']) || /health_playerstate_watch_sample_count\s*=\s*[1-9]/i.test(facts.text)) {
    add('health-playerstate-watch', 'Imported evidence contains PlayerState health watch samples.');
  }

  return { completed, facts };
}

function completedPhaseIds(state) {
  return new Set((state.completedPhases || []).map((entry) => entry.phaseId || entry));
}

function failedPhaseIds(state) {
  return new Set((state.failedPhases || []).map((entry) => entry.phaseId || entry));
}

function blockedPhaseIds(state) {
  return new Set((state.blockedPhases || []).map((entry) => entry.phaseId || entry));
}

function findNextRunnablePhase(plan, state) {
  const completed = completedPhaseIds(state);
  const failed = failedPhaseIds(state);
  const blocked = blockedPhaseIds(state);
  for (const phase of plan.phases) {
    if (completed.has(phase.phaseId) || failed.has(phase.phaseId) || blocked.has(phase.phaseId)) continue;
    if (phase.implemented !== true) continue;
    gateConfigForPhase(phase);
    return phase;
  }
  return null;
}

function reconcileState(plan, state = null, repoRoot = process.cwd()) {
  const existing = state || {};
  const seeded = state ? { completed: [], facts: evidenceFacts(repoRoot) } : seedCompletionsFromEvidence(plan, repoRoot);
  const completedById = new Map();
  for (const entry of [...(seeded.completed || []), ...(existing.completedPhases || [])]) {
    const phaseId = entry.phaseId || entry;
    if (phaseId && !completedById.has(phaseId)) {
      completedById.set(phaseId, typeof entry === 'string' ? { phaseId, status: 'complete' } : entry);
    }
  }

  const blockedById = new Map();
  for (const phase of plan.phases) {
    if (phase.implemented !== true) {
      blockedById.set(phase.phaseId, {
        phaseId: phase.phaseId,
        status: 'blocked',
        reason: phase.blockedReason || 'Probe set is not implemented yet.'
      });
    }
  }
  for (const entry of existing.blockedPhases || []) {
    const phaseId = entry.phaseId || entry;
    if (phaseId) blockedById.set(phaseId, typeof entry === 'string' ? { phaseId, status: 'blocked' } : entry);
  }

  const out = {
    schemaVersion: 1,
    campaign: plan.campaign,
    planPath: PLAN_PATH.replace(/\\/g, '/'),
    createdAt: existing.createdAt || nowIso(),
    updatedAt: nowIso(),
    completedPhases: Array.from(completedById.values()),
    failedPhases: existing.failedPhases || [],
    blockedPhases: Array.from(blockedById.values()),
    currentPhase: existing.currentPhase || null,
    nextRecommendedPhase: null,
    latestSessionId: existing.latestSessionId || seeded.facts.latestSessionId || '',
    latestCommit: existing.latestCommit || seeded.facts.latestCommit || '',
    latestSummaryPath: existing.latestSummaryPath || seeded.facts.latestSummaryPath || '',
    phaseStatuses: {}
  };

  for (const phase of plan.phases) {
    out.phaseStatuses[phase.phaseId] = {
      status: 'pending',
      riskTier: phase.riskTier,
      probeSet: phase.probeSet,
      tickDriver: phase.tickDriver,
      mode: phase.mode
    };
  }
  for (const entry of out.completedPhases) out.phaseStatuses[entry.phaseId].status = 'complete';
  for (const entry of out.failedPhases) out.phaseStatuses[entry.phaseId].status = entry.status || 'failed';
  for (const entry of out.blockedPhases) {
    if (out.phaseStatuses[entry.phaseId]) {
      out.phaseStatuses[entry.phaseId].status = 'blocked';
      out.phaseStatuses[entry.phaseId].reason = entry.reason || '';
    }
  }
  if (out.currentPhase && out.phaseStatuses[out.currentPhase] && out.phaseStatuses[out.currentPhase].status === 'pending') {
    out.phaseStatuses[out.currentPhase].status = 'current';
  }

  const next = findNextRunnablePhase(plan, out);
  out.nextRecommendedPhase = next ? next.phaseId : null;
  return out;
}

function markPrepared(plan, state, phaseId, commit) {
  const phase = plan.phases.find((item) => item.phaseId === phaseId);
  if (!phase) throw new Error(`Unknown phase: ${phaseId}`);
  gateConfigForPhase(phase);
  const out = reconcileState(plan, state);
  out.currentPhase = phaseId;
  out.latestCommit = commit || out.latestCommit || '';
  out.updatedAt = nowIso();
  if (out.phaseStatuses[phaseId]) out.phaseStatuses[phaseId].status = 'current';
  return out;
}

function markCollected(plan, state, phaseId, result) {
  const out = reconcileState(plan, state);
  out.currentPhase = null;
  out.latestSessionId = result.latestSessionId || out.latestSessionId || '';
  out.latestCommit = result.latestCommit || out.latestCommit || '';
  out.latestSummaryPath = result.latestSummaryPath || out.latestSummaryPath || '';

  out.completedPhases = (out.completedPhases || []).filter((entry) => (entry.phaseId || entry) !== phaseId);
  out.failedPhases = (out.failedPhases || []).filter((entry) => (entry.phaseId || entry) !== phaseId);

  if (result.status === 'passed') {
    out.completedPhases.push({
      phaseId,
      status: 'complete',
      completedAt: nowIso(),
      source: 'campaign-collect',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  } else {
    out.failedPhases.push({
      phaseId,
      status: result.status || 'failed',
      failedAt: nowIso(),
      reason: result.reason || '',
      latestSessionId: out.latestSessionId,
      latestCommit: out.latestCommit,
      latestSummaryPath: out.latestSummaryPath
    });
  }
  return reconcileState(plan, out);
}

function phaseStatus(state, phaseId) {
  if ((state.completedPhases || []).some((entry) => (entry.phaseId || entry) === phaseId)) return 'complete';
  if ((state.failedPhases || []).some((entry) => (entry.phaseId || entry) === phaseId)) return 'failed';
  if ((state.blockedPhases || []).some((entry) => (entry.phaseId || entry) === phaseId)) return 'blocked';
  if (state.currentPhase === phaseId) return 'current';
  return 'pending';
}

function listByStatus(plan, state, status) {
  return plan.phases.filter((phase) => phaseStatus(state, phase.phaseId) === status);
}

function renderList(phases, fallback = 'None.') {
  if (!phases.length) return `- ${fallback}\n`;
  return phases.map((phase) => `- \`${phase.phaseId}\` - ${phase.label}\n`).join('');
}

function generateCampaignStatusMarkdown(plan, state, repoRoot = process.cwd()) {
  const facts = evidenceFacts(repoRoot);
  let out = '# Campaign Status\n\n';
  out += `- Campaign: \`${plan.campaign}\`\n`;
  out += `- Updated: ${state.updatedAt || nowIso()}\n`;
  out += `- Current phase: ${state.currentPhase ? `\`${state.currentPhase}\`` : 'none'}\n`;
  out += `- Next recommended phase: ${state.nextRecommendedPhase ? `\`${state.nextRecommendedPhase}\`` : 'none'}\n`;
  out += `- Latest session: ${state.latestSessionId || 'none'}\n`;
  out += `- Latest commit: ${state.latestCommit || 'none'}\n`;
  out += `- Latest summary: ${state.latestSummaryPath || 'none'}\n\n`;

  out += '## Completed Phases\n\n';
  out += renderList(listByStatus(plan, state, 'complete'));
  out += '\n## Failed Phases\n\n';
  out += renderList(listByStatus(plan, state, 'failed'));
  out += '\n## Blocked Phases\n\n';
  const blocked = listByStatus(plan, state, 'blocked');
  if (!blocked.length) {
    out += '- None.\n';
  } else {
    for (const phase of blocked) {
      const entry = (state.blockedPhases || []).find((item) => item.phaseId === phase.phaseId) || {};
      out += `- \`${phase.phaseId}\` - ${phase.label}: ${entry.reason || phase.blockedReason || 'blocked'}\n`;
    }
  }
  out += '\n## Pending Phases\n\n';
  out += renderList(listByStatus(plan, state, 'pending'));

  out += '\n## Confirmed Safe Paths\n\n';
  const safeSignals = [];
  if (/CrabPS\.GetPropertyValue\.WeaponDA/.test(facts.text)) safeSignals.push('`CrabPS.WeaponDA` via `GetPropertyValue`');
  if (/CrabPS\.GetPropertyValue\.AbilityDA/.test(facts.text)) safeSignals.push('`CrabPS.AbilityDA` via `GetPropertyValue`');
  if (/CrabPS\.GetPropertyValue\.MeleeDA/.test(facts.text)) safeSignals.push('`CrabPS.MeleeDA` via `GetPropertyValue`');
  if (/Health\.PlayerState\.Sample|CrabPS\.HealthInfo/.test(facts.text)) safeSignals.push('`CrabPC -> PlayerState -> CrabPS -> HealthInfo` read-only PlayerState health path');
  if (!safeSignals.length) out += '- None imported yet.\n';
  else out += safeSignals.map((item) => `- ${item}\n`).join('');

  out += '\n## Confirmed Unsafe Paths\n\n';
  out += '- HUD ReceiveDrawHUD tick hook remains blocked by default.\n';
  out += '- `FindFirstOf.CrabHC` is not confirmed as a player-health source; imported evidence has seen an unscoped destructible/barrel candidate.\n';
  out += '- Writes and RPCs are disabled and are outside this campaign version.\n';

  out += '\n## Untested Paths\n\n';
  out += '- Multiplayer health scaling remains unproven until `multiplayer-health-playerstate-watch` evidence exists.\n';
  out += '- Crystals, slots, inventory arrays, `InventoryInfo`, and enhancements are placeholders until explicit probe sets are implemented.\n';
  out += '- Deep arrays and InventoryInfo gates remain off until their explicit reviewed phases.\n';

  out += '\n## Safety Gate Summary\n\n';
  out += '- Default config remains `tickDriver = none`, `probeSet = shallow-core`, and all research gates false.\n';
  out += '- Campaign read phases never enable writes, RPCs, or HUD hooks.\n';
  out += '- `allowHealthProbes` is enabled only for explicit health phases.\n';
  out += '- `allowDeepArrayProbes` and `allowInventoryInfoProbes` are not enabled by implemented phases.\n';
  return out;
}

module.exports = {
  ALL_GATES,
  CAMPAIGN,
  DOC_PATH,
  PLAN_PATH,
  STATE_PATH,
  completedPhaseIds,
  evidenceFacts,
  findNextRunnablePhase,
  gateConfigForPhase,
  generateCampaignStatusMarkdown,
  loadPlan,
  markCollected,
  markPrepared,
  nowIso,
  readJsonIfExists,
  reconcileState,
  seedCompletionsFromEvidence,
  validatePhaseSafety,
  writeJson
};
