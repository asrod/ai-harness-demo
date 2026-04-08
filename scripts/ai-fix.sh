#!/usr/bin/env bash
# 测试失败后的修复：优先 OpenAI（OPENAI_API_KEY），否则 mock（perl 替换）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SERVER_FILE="app/server.js"

if [[ ! -f "$SERVER_FILE" ]]; then
  echo "[ai-fix] ERROR: missing $SERVER_FILE"
  exit 1
fi

BEFORE=$(mktemp)
trap 'rm -f "$BEFORE"' EXIT
cp "$SERVER_FILE" "$BEFORE"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  _BASE="${OPENAI_API_BASE:-${OPENAI_BASE_URL:-https://api.openai.com/v1}}"
  echo "[ai-fix] 模式: 真实 LLM（非规则替换）"
  echo "[ai-fix] 端点: ${_BASE}/chat/completions"
  echo "[ai-fix] 模型: ${OPENAI_MODEL:-gpt-4o-mini}"
  echo "[ai-fix] 说明: 将当前 app/server.js 与失败用例的契约发给模型，由模型返回整文件后落盘"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  node scripts/openai-apply.js
else
  echo "[ai-fix] 模式: mock（无 OPENAI_API_KEY，仅演示 Harness 流程）"
  echo "[ai-fix] 规则: 把字面量 'wrong' → 'world'（固定替换，不是 LLM）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  perl -i -pe "s/'wrong'/'world'/" "$SERVER_FILE"
  echo "[ai-fix] 已用 perl 完成 mock 补丁"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  此处可见「AI / 修复逻辑」对源码的实际改动（unified diff）     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
diff -u "$BEFORE" "$SERVER_FILE" || true
echo ""

if git rev-parse --git-dir >/dev/null 2>&1; then
  git config user.name "${GIT_AUTHOR_NAME:-AI Harness}"
  git config user.email "${GIT_AUTHOR_EMAIL:-ai-harness@local}"

  # PR 事件：留在当前 PR 头部分支，推送后 PR 上会出现「AI 修复」新 commit
  if [[ "${GITHUB_ACTIONS:-}" == "true" && -n "${GITHUB_HEAD_REF:-}" ]]; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" == "HEAD" ]]; then
      echo "[ai-fix] Checking out PR head: $GITHUB_HEAD_REF"
      git checkout "$GITHUB_HEAD_REF"
      BRANCH="$GITHUB_HEAD_REF"
    fi
    echo "[ai-fix] PR harness: repair commit will push to branch «$BRANCH» (updates open PR)"
  else
    BRANCH="fix/ai-repair"
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git checkout "$BRANCH"
    else
      git checkout -b "$BRANCH"
    fi
    echo "[ai-fix] Push branch: $BRANCH"
  fi

  git add "$SERVER_FILE"
  if git diff --cached --quiet; then
    echo "[ai-fix] No staged changes (already fixed?)"
  else
    MSG="fix(hello): AI harness repair — align /hello with Karate contract"
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
