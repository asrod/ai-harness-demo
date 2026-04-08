# AI Harness Demo

最小可运行的演示：**自动起服务 → 跑 API 测试 → 失败则模拟 AI 修代码 → 重启服务并重跑测试**；在本地与 GitHub Actions 中均可执行。

## 什么是 Harness？

在工程里，**Harness（测试/执行外骨骼）**指把「环境准备、被测程序生命周期、测试执行、结果判定、后续动作（如重试、报告、触发修复）」编排在一起的**自动化执行层**。它把零散命令变成一条可重复、可上 CI 的流水线，让你专注在「测什么」而不是每次手动敲一堆步骤。

## 本 Demo 如何体现 Harness？

| 步骤 | 说明 |
|------|------|
| 启动服务 | `harness.sh` 后台启动 `app/server.js`，并轮询直到 `/hello` 可用 |
| 执行测试 | 调用 `mvn test` 运行 Karate（`test/hello.feature`） |
| 判定 | 成功则退出 0；失败则进入修复路径 |
| 失败后续 | 打印 **AI 修复阶段**横幅、`AI repairing...`，执行 `ai-fix.sh`（会打印 **LLM 请求信息** 与 **`diff` 前后对比**），重启 Node 后还会 **curl 打印 `/hello` 响应**，再跑 `mvn test` |

脚本即 Harness 入口：`scripts/harness.sh`。

## 什么是 AI Harness？

**AI Harness** 在普通 Harness 上增加一环：**当测试失败时，自动修复代码并提交**。若设置了环境变量 `OPENAI_API_KEY`，`scripts/ai-fix.sh` 会调用 `scripts/openai-apply.js` 请求 OpenAI（JSON 模式，返回完整 `app/server.js`）；否则使用 **mock**（`perl` 将 `'wrong'` 改为 `'world'`）。修复后会在分支 `fix/ai-repair` 上提交；在 GitHub Actions 中还会尝试 `git push`。

## 本地运行

前置：**Node.js 18+**、**JDK 17+**、**Maven**、**curl**。

```bash
cd ai-harness-demo
chmod +x scripts/harness.sh scripts/ai-fix.sh
git init   # 若需体验 AI 修复后的分支与 commit
bash scripts/harness.sh
```

首次运行：`server.js` 故意返回错误，Karate 失败 → mock AI 修复 → 服务重启 → 第二次测试通过。

仅启动服务（调试用）：

```bash
node app/server.js
# 另开终端: mvn test
```

## GitHub Actions

推送至 GitHub 后，工作流 `.github/workflows/ci.yml` 会安装 Node/Java/Maven，执行 `harness.sh`。`permissions: contents: write` 用于在修复后向 `fix/ai-repair` 推送提交（受分支保护策略影响时可能推送失败，日志中会有提示）。

### 用 `gh` 建库并配置 OpenAI（勿在聊天里发送密钥）

1. 安装并登录 [GitHub CLI](https://cli.github.com/)：`gh auth login`
2. 在本目录创建并推送仓库（示例仓库名可改）：

   ```bash
   gh repo create YOUR_ORG/ai-harness-demo --public --source=. --remote=origin --push
   ```

3. **在 GitHub 上要配三项**（CI 与工作流一致）：

   | 配置项 | 放哪里 | 含义 |
   |--------|--------|------|
   | `OPENAI_API_KEY` | **Secrets** | OpenAI API 密钥（`sk-...`） |
   | `OPENAI_API_BASE` | **Variables** | API 根地址，如 `https://api.openai.com/v1`（不要末尾 `/`） |
   | `OPENAI_MODEL` | **Variables** | 模型名，如 `gpt-4o-mini`、`gpt-4o` |

   **Secret（仅在本机终端执行，勿把 key 发到聊天）：**

   ```bash
   gh secret set OPENAI_API_KEY --repo YOUR_ORG/ai-harness-demo
   ```

   **Variables（可明文，适合 URL 与模型名）：**

   ```bash
   gh variable set OPENAI_API_BASE --body "https://api.openai.com/v1" --repo YOUR_ORG/ai-harness-demo
   gh variable set OPENAI_MODEL --body "gpt-4o-mini" --repo YOUR_ORG/ai-harness-demo
   ```

   也可在网页：**Settings → Secrets and variables → Actions** 中分别添加。

   未配置 `OPENAI_API_KEY` 时 CI 仍会通过（走 **mock** 修复）。配置了 Key 但未设 Variable 时：`OPENAI_API_BASE` / `OPENAI_MODEL` 会用脚本内默认值（官方地址 + `gpt-4o-mini`）。

4. 在 **Actions** 里 **Re-run** 一次 workflow，或向 `main` 再推一个 commit。

**本地跑 harness 并走真实 OpenAI**（二选一，勿泄露 key）：

1. **推荐：`.env` 文件**（`harness.sh` 会自动 `source`；`.env` 已在 `.gitignore` 中）  
   - 复制模板：`cp .env.example .env`  
   - 编辑 `.env`，设置 `OPENAI_API_KEY=你的密钥`；模板里已含 aihubmix 示例：`OPENAI_API_BASE=https://aihubmix.com/v1`、`OPENAI_MODEL=gpt-4.1-mini-free`。  
   - 实际请求地址为 `{OPENAI_API_BASE}/chat/completions`（与 `https://aihubmix.com/v1/chat/completions` 一致）。

2. **或当前 shell 导出：**

```bash
export OPENAI_API_KEY="你的密钥"   # 必填
export OPENAI_API_BASE="https://aihubmix.com/v1"
export OPENAI_MODEL="gpt-4.1-mini-free"
```

（`OPENAI_BASE_URL` 与 `OPENAI_API_BASE` 等价，任选其一。）

## 项目结构

```
ai-harness-demo/
├── app/server.js
├── test/hello.feature          # Karate 特性文件（pom.xml 将其加入 test classpath）
├── src/test/java/demo/HelloApiTest.java   # JUnit5 + Karate 入口（指向 hello.feature）
├── scripts/harness.sh
├── scripts/ai-fix.sh
├── scripts/openai-apply.js   # 可选：OPENAI_API_KEY 时由 ai-fix 调用
├── package.json
├── pom.xml
└── .github/workflows/ci.yml
```

Maven 需要至少一个 Java 测试类触发 Surefire；该类仅负责加载根目录下的 `test/hello.feature`。

## 许可

演示用途，按需修改。
