#!/usr/bin/env node
const path = require('path');
const fs = require('fs');
const {
  DOC_PATH,
  STATE_PATH,
  generateCampaignStatusMarkdown,
  loadPlan,
  readJsonIfExists,
  reconcileState,
  writeJson
} = require('./campaign_helpers');

function arg(name) {
  const idx = process.argv.indexOf(name);
  return idx >= 0 ? process.argv[idx + 1] : null;
}

function hasFlag(name) {
  return process.argv.includes(name);
}

const repoRoot = process.cwd();
const statePath = path.resolve(arg('--state') || path.join(repoRoot, STATE_PATH));
const docPath = path.resolve(arg('--out') || path.join(repoRoot, DOC_PATH));
const quiet = hasFlag('--quiet');
const writeState = hasFlag('--write-state') || !hasFlag('--no-write-state');

const plan = loadPlan(repoRoot);
const existingState = readJsonIfExists(statePath);
const state = reconcileState(plan, existingState, repoRoot);

if (writeState) {
  writeJson(statePath, state);
}

fs.mkdirSync(path.dirname(docPath), { recursive: true });
fs.writeFileSync(docPath, generateCampaignStatusMarkdown(plan, state, repoRoot));

if (!quiet) {
  console.log(`campaign status generated = ${path.relative(repoRoot, docPath)}`);
  console.log(`campaign state = ${path.relative(repoRoot, statePath)}`);
  console.log(`nextRecommendedPhase = ${state.nextRecommendedPhase || 'none'}`);
}
