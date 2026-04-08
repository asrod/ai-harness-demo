#!/usr/bin/env bash
# 测试失败后的修复：优先 OpenAI（OPENAI_API_KEY），否则 mock（perl 替换）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SERVER_FILE="app/server.js"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  echo "[ai-fix] Mode: OpenAI API"
  echo "[ai-fix] Model: ${OPENAI_MODEL:-gpt-4o-mini}"
  echo "[ai-fix] Reasoning: delegating code repair to LLM (JSON fullFile response)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  node scripts/openai-apply.js
else
  echo "[ai-fix] Mode: mock (no OPENAI_API_KEY)"
  echo "[ai-fix] Reasoning:"
  echo "  - 测试期望 GET /hello 返回 JSON: { message: 'world' }"
  echo "  - 当前实现返回 'wrong'，与契约不一致"
  echo "  - 行动：将错误字面量改为 'world'"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ ! -f "$SERVER_FILE" ]]; then
    echo "[ai-fix] ERROR: missing $SERVER_FILE"
    exit 1
  fi
  perl -i -pe "s/'wrong'/'world'/" "$SERVER_FILE"
  echo "[ai-fix] Patched $SERVER_FILE (mock)"
fi

if git rev-parse --git-dir >/dev/null 2>&1; then
  git config user.name "${GIT_AUTHOR_NAME:-AI Harness}"
  git config user.email "${GIT_AUTHOR_EMAIL:-ai-harness@local}"

  BRANCH="fix/ai-repair"
  if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git checkout "$BRANCH"
  else
    git checkout -b "$BRANCH"
  fi

  git add "$SERVER_FILE"
  if git diff --cached --quiet; then
    echo "[ai-fix] No staged changes (already fixed?)"
  else
    MSG="fix(hello): align /hello response with API contract (AI repair)"
    git commit -m "$MSG"
    echo "[ai-fix] Committed on branch $BRANCH"
  fi

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    git push -u origin "$BRANCH" || {
      echo "[ai-fix] WARN: git push failed (check token / branch protection)."
    }
  fi
else
  echo "[ai-fix] Not a git repository — skipped branch/commit (local file still patched)."
fi

echo "[ai-fix] Done."
