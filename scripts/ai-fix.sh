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
  echo "[ai-fix] 说明: 读取 test/*.feature 作为契约，由模型改写源码并生成 commit 标题/正文"
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
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
    git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
  else
    git config user.name "${GIT_AUTHOR_NAME:-AI Harness}"
    git config user.email "${GIT_AUTHOR_EMAIL:-ai-harness@local}"
  fi

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
    COMMIT_TMP=$(mktemp)
    if [[ -n "${OPENAI_API_KEY:-}" ]] && [[ -f "$ROOT/.harness-ai-commit.json" ]]; then
      node "$ROOT/scripts/git-commit-from-ai-json.js" "$ROOT/.harness-ai-commit.json" "$COMMIT_TMP"
      rm -f "$ROOT/.harness-ai-commit.json"
      git commit -F "$COMMIT_TMP"
    else
      # mock：无 LLM，提交说明保持通用，不写死某条 API/测试名
      printf '%s\n\n%s\n' \
        "chore: harness mock patch (rule-based, not LLM)" \
        "No OPENAI_API_KEY: applied fixed string replacement only. Configure a key for model-written code and commit messages tied to test/*.feature." \
        > "$COMMIT_TMP"
      git commit -F "$COMMIT_TMP"
    fi
    rm -f "$COMMIT_TMP"
    echo "[ai-fix] Committed on branch $BRANCH"
  fi

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    if ! git push -u origin "$BRANCH"; then
      echo "[ai-fix] ERROR: git push failed (check token / branch protection)." >&2
      exit 1
    fi
  fi
else
  echo "[ai-fix] Not a git repository — skipped branch/commit (local file still patched)."
fi

echo "[ai-fix] Done."
