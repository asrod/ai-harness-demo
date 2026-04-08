#!/usr/bin/env bash
# Harness：启动服务 → 跑测试 → 失败则触发 AI 修复 → 重跑测试
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PORT="${PORT:-3000}"
export PORT

cleanup() {
  if [[ -n "${SERVER_PID:-}" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[harness] Stopping server (pid $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[harness] Starting Node server..."
node app/server.js &
SERVER_PID=$!

echo "[harness] Waiting for http://127.0.0.1:${PORT}/hello ..."
ready=0
for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:${PORT}/hello" >/dev/null; then
    ready=1
    break
  fi
  sleep 0.2
done
if [[ "$ready" -ne 1 ]]; then
  echo "[harness] ERROR: server did not become ready in time."
  exit 1
fi

run_tests() {
  mvn -B test
}

echo "[harness] Running Karate (mvn test)..."
if run_tests; then
  echo "[harness] Tests passed. Done."
  exit 0
fi

echo "[harness] Tests failed."
echo "[harness] AI repairing..."
bash scripts/ai-fix.sh

echo "[harness] Restarting server to load patched code..."
cleanup
trap - EXIT
trap cleanup EXIT
node app/server.js &
SERVER_PID=$!

echo "[harness] Waiting for server after patch..."
ready=0
for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:${PORT}/hello" >/dev/null; then
    ready=1
    break
  fi
  sleep 0.2
done
if [[ "$ready" -ne 1 ]]; then
  echo "[harness] ERROR: server did not become ready after patch."
  exit 1
fi

echo "[harness] Re-running tests after AI fix..."
if run_tests; then
  echo "[harness] Tests passed after repair. Done."
  exit 0
fi

echo "[harness] ERROR: tests still failing after repair."
exit 1
