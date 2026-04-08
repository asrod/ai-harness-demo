#!/usr/bin/env node
'use strict';
/** 将 openai-apply 写的 .harness-ai-commit.json 格式化为 git commit -F 用的纯文本 */
const fs = require('fs');

const [, , jsonPath, outPath] = process.argv;
if (!jsonPath || !outPath) {
  console.error('usage: git-commit-from-ai-json.js <json-path> <out-path>');
  process.exit(1);
}
const j = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
const sub = String(j.commitSubject || j.subject || 'fix: automated repair after failing tests').trim();
const body = String(j.commitBody || j.body || '').trim();
const text = sub + (body ? `\n\n${body}` : '') + '\n';
fs.writeFileSync(outPath, text, 'utf8');
