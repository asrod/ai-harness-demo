#!/usr/bin/env node
'use strict';

/**
 * 使用 OpenAI Chat Completions（JSON 模式）重写 app/server.js。
 * 环境变量：OPENAI_API_KEY（必填）、OPENAI_MODEL（默认 gpt-4o-mini）、OPENAI_API_BASE（默认 https://api.openai.com/v1）
 */
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const serverPath = path.join(root, 'app', 'server.js');

const key = process.env.OPENAI_API_KEY;
if (!key || !String(key).trim()) {
  console.error('[openai-apply] OPENAI_API_KEY is missing or empty');
  process.exit(1);
}

const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
const apiBase = (process.env.OPENAI_API_BASE || 'https://api.openai.com/v1').replace(/\/$/, '');
const url = `${apiBase}/chat/completions`;

const current = fs.readFileSync(serverPath, 'utf8');

const body = {
  model,
  response_format: { type: 'json_object' },
  messages: [
    {
      role: 'system',
      content:
        'You output only valid JSON. No markdown fences. Keys must match the user schema exactly.',
    },
    {
      role: 'user',
      content: `File app/server.js (full contents):\n\n${current}\n\n---\n` +
        'Karate API test: GET /hello must return HTTP 200 and JSON body exactly {"message":"world"}.\n' +
        'Return a JSON object: {"fullFile":"<entire corrected file as one string with \\n for newlines>"}.\n' +
        'Preserve structure, comments, and style; change only what is needed to satisfy the test.',
    },
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
  if (typeof full !== 'string' || !full.includes('createServer')) {
    console.error('[openai-apply] Invalid fullFile in model response');
    process.exit(1);
  }

  fs.writeFileSync(serverPath, full, 'utf8');
  console.log('[openai-apply] Wrote app/server.js (' + full.split('\n').length + ' lines)');
}

main().catch((e) => {
  console.error('[openai-apply]', e);
  process.exit(1);
});
