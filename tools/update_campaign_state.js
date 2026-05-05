#!/usr/bin/env node
const path = require('path');
const {
  STATE_PATH,
  loadPlan,
  markCollected,
  markPrepared,
  readJsonIfExists,
  reconcileState,
  writeJson
} = require('./campaign_helpers');

function arg(name) {
  const idx = process.argv.indexOf(name);
  return idx >= 0 ? process.argv[idx + 1] : null;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

const action = process.argv[2];
const repoRoot = process.cwd();
const statePath = path.resolve(arg('--state') || path.join(repoRoot, STATE_PATH));
const plan = loadPlan(repoRoot);
const existingState = readJsonIfExists(statePath);
let state = reconcileState(plan, existingState, repoRoot);

if (action === 'init') {
  state = reconcileState(plan, existingState, repoRoot);
} else if (action === 'prepare') {
  const phaseId = arg('--phase');
  if (!phaseId) fail('prepare requires --phase <phaseId>');
  state = markPrepared(plan, state, phaseId, arg('--commit') || '');
} else if (action === 'collect') {
  const phaseId = arg('--phase');
  const status = arg('--status') || 'failed';
  if (!phaseId) fail('collect requires --phase <phaseId>');
  state = markCollected(plan, state, phaseId, {
    status,
    reason: arg('--reason') || '',
    latestSessionId: arg('--latest-session') || '',
    latestCommit: arg('--latest-commit') || '',
    latestSummaryPath: arg('--latest-summary') || ''
  });
} else {
  fail('Usage: node tools/update_campaign_state.js <init|prepare|collect> --state <path> [args]');
}

writeJson(statePath, state);
console.log(`nextRecommendedPhase = ${state.nextRecommendedPhase || 'none'}`);
