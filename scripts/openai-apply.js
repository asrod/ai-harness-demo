#!/usr/bin/env node
'use strict';

/**
 * 使用 OpenAI Chat Completions（JSON 模式）重写 app/server.js，并由模型生成 commit 标题/正文。
 * 环境变量：OPENAI_API_KEY、OPENAI_MODEL、OPENAI_API_BASE / OPENAI_BASE_URL（同前）
 * 可选：HARNESS_SERVER_FILE（默认 app/server.js）
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const serverRel = process.env.HARNESS_SERVER_FILE || 'app/server.js';
const serverPath = path.join(root, serverRel);

const key = process.env.OPENAI_API_KEY;
if (!key || !String(key).trim()) {
  console.error('[openai-apply] OPENAI_API_KEY is missing or empty');
  process.exit(1);
}

const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const apiBase = (
  process.env.OPENAI_API_BASE ||
  process.env.OPENAI_BASE_URL ||
  'https://api.openai.com/v1'
).replace(/\/$/, '');
const url = `${apiBase}/chat/completions`;

function loadFeatureSpecs() {
  const testDir = path.join(root, 'test');
  if (!fs.existsSync(testDir)) {
    return '(no test/ directory)';
  }
  const files = fs.readdirSync(testDir).filter((f) => f.endsWith('.feature'));
  if (files.length === 0) {
    return '(no *.feature under test/)';
  }
  return files
    .map((f) => `### test/${f}\n${fs.readFileSync(path.join(testDir, f), 'utf8')}`)
    .join('\n\n');
}

const current = fs.readFileSync(serverPath, 'utf8');
const featureBlock = loadFeatureSpecs();
const extraHint = (process.env.HARNESS_CONTRACT_HINT || '').trim();

console.log('[openai-apply] ── LLM 介入 ──');
console.log('[openai-apply] 请求:', 'POST', url);
console.log('[openai-apply] 模型:', model);
console.log('[openai-apply] 目标文件:', serverRel, '（', current.split('\n').length, '行）');

const userPrompt =
  `You are fixing application code so that the automated API test suite passes.\n\n` +
  `## Files under test/ (Karate / Gherkin — this is the source of truth for expected behavior)\n\n${featureBlock}\n\n` +
  (extraHint ? `## Additional hint from harness (optional)\n${extraHint}\n\n` : '') +
  `## Current ${serverRel} (full file)\n\n${current}\n\n` +
  `---\n` +
  `Tasks:\n` +
  `1) Rewrite ${serverRel} as needed so ALL scenarios in the feature files above pass. The failure domain is not fixed to any single route or message — infer from the features.\n` +
  `2) Return JSON with exactly these keys:\n` +
  `   - "fullFile": string, the entire corrected file (use \\n for newlines).\n` +
  `   - "commitSubject": string, first line of git commit, <= 72 chars, conventional-commit style when appropriate. Must be YOUR original summary of this specific fix (no canned phrases like "align with Karate contract").\n` +
  `   - "commitBody": string, optional multi-line body: what was wrong, what you changed, and why. Again, be specific to this diff; do not paste boilerplate from these instructions.\n` +
  `Preserve unrelated structure/comments in fullFile when possible.`;

const body = {
  model,
  response_format: { type: 'json_object' },
  messages: [
    {
      role: 'system',
      content:
        'You output only valid JSON. No markdown code fences. Include keys fullFile, commitSubject, and commitBody as requested.',
    },
    { role: 'user', content: userPrompt },
  ],
};

async function main() {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const raw = await res.text();
  if (!res.ok) {
    console.error('[openai-apply] API HTTP', res.status, raw.slice(0, 2000));
    process.exit(1);
  }

  let data;
  try {
    data = JSON.parse(raw);
  } catch (e) {
    console.error('[openai-apply] Invalid JSON from API');
    process.exit(1);
  }

  const text = data.choices?.[0]?.message?.content;
  if (!text) {
    console.error('[openai-apply] Empty choices:', raw.slice(0, 1500));
    process.exit(1);
  }

  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (e) {
    console.error('[openai-apply] Model did not return JSON object:', text.slice(0, 1500));
    process.exit(1);
  }

  const full = parsed.fullFile;
  if (typeof full !== 'string' || full.length < 20) {
    console.error('[openai-apply] Invalid or empty fullFile in model response');
    process.exit(1);
  }

  let commitSubject =
    typeof parsed.commitSubject === 'string' ? parsed.commitSubject.trim() : '';
  let commitBody = typeof parsed.commitBody === 'string' ? parsed.commitBody.trim() : '';
  if (!commitSubject) {
    commitSubject = 'fix: automated repair after failing API tests';
  }

  fs.writeFileSync(serverPath, full, 'utf8');
  const metaPath = path.join(root, '.harness-ai-commit.json');
  fs.writeFileSync(
    metaPath,
    JSON.stringify({ commitSubject, commitBody }, null, 2),
    'utf8',
  );

  console.log(
    '[openai-apply] LLM 已写入',
    serverRel,
    '（',
    full.split('\n').length,
    '行）',
  );
  console.log('[openai-apply] 模型生成的提交标题:', commitSubject);
  if (commitBody) {
    console.log('[openai-apply] 提交正文（摘要）:', commitBody.split('\n')[0].slice(0, 120) + (commitBody.length > 120 ? '…' : ''));
  }
  console.log('[openai-apply] ── LLM 调用结束（下方 ai-fix 会打印 diff 并 git commit -F）──');
}

main().catch((e) => {
  console.error('[openai-apply]', e);
  process.exit(1);
});
