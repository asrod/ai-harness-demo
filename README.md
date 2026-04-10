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

**AI Harness** 在普通 Harness 上增加一环：**当测试失败时，自动修复代码并提交**。若设置了 `OPENAI_API_KEY`，`openai-apply.js` 会把 **`test/*.feature` 全文**作为契约交给模型，改写 **`HARNESS_SERVER_FILE`（默认 `app/server.js`）**，并由模型生成 **`commitSubject` / `commitBody`**（`git commit -F`，不是写死的 “align /hello…”）。未配置 Key 时使用 **mock**（`perl` 替换 `'wrong'`→`'world'`），提交说明为通用占位。可选环境变量 **`HARNESS_CONTRACT_HINT`** 可再给模型一句补充说明。

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

推送至 GitHub 后，工作流 `.github/workflows/ci.yml` 会安装 Node/Java/Maven，执行 `harness.sh`（内含 Karate API 测试）。`permissions: contents: write` 用于在修复后向 PR 分支或 `fix/ai-repair` 推送提交（受分支保护策略影响时可能推送失败，日志中会有提示）。

### 合并 PR 前必须跑通测试（必过检查）

GitHub **不会**自动把「测试通过」当成合并门槛，需要在仓库里打开 **分支保护 / 规则**：

**方式 A：经典分支保护（Branch protection rule）**

1. 打开 **Settings → Branches → Branch protection rules → Add rule**（或编辑已有 `main` 规则）。
2. **Branch name pattern** 填 `main`。
3. 勾选 **Require status checks to pass before merging**。
4. 在 **Status checks that are required** 里添加：**`PR Karate Harness`**（对应本仓库 workflow **AI Harness Demo** 里的 job 显示名）。  
   - 若下拉列表里没有：先在 `main` 上跑成功一次该 workflow，或开/更一个 PR 让检查出现过，再回来添加。
5. （推荐）勾选 **Require branches to be up to date before merging**，避免在落后 `main` 的基底上直接合并。

**方式 B：规则集（Settings → Rules → Rulesets）**

新建针对 `main` 的 Ruleset，启用 **Require status checks**，同样把 **`PR Karate Harness`** 设为必选。

配置完成后：PR 在 **Checks** 里该项未通过（或仍为失败）时，**Merge** 会被禁用，直到 Harness/Karate 通过（含 AI 自动修复后再次跑绿的情况）。

### PR 上 AI 已推修复，但仍显示 Blocked / 没有 Checks？

**原因：** 工作流里用默认 **`GITHUB_TOKEN`** 执行 `git push` 时，GitHub **故意不会再触发**新的 Actions（避免无限循环），因此**机器人新推上去的那个 commit 上不会出现「PR Karate Harness」**。分支保护要求该检查通过时，界面会一直卡在 **Blocked**，即使代码已经修好。

**临时解决（任选其一）：**

- 本地往 PR 分支推一个空提交：  
  `git checkout <PR 头分支> && git commit --allow-empty -m "chore: trigger CI" && git push`
- 或使用 **Actions → AI Harness Demo → Run workflow**，在 **ref** 里填 PR 头分支名（如 `feat/test-AI`），在最新代码上再跑一轮检查。

**推荐根治：配置 `AI_HARNESS_PUSH_TOKEN`**

Workflow 里 checkout 使用 **`secrets.AI_HARNESS_PUSH_TOKEN || secrets.GITHUB_TOKEN`**（见 `.github/workflows/ci.yml`）。配置 PAT 后，机器人用该凭据推送的 commit 会**再次触发** Actions，必选检查会出现在**最新** commit 上。

1. **创建 Fine-grained PAT**  
   - 打开 [Personal access tokens（Fine-grained）](https://github.com/settings/tokens?type=beta) → **Generate new token**。  
   - **Repository access**：只选本仓库（例如 `YOUR_ORG/ai-harness-demo`）。  
   - **Repository permissions → Contents**：**Read and write**（推送修复 commit 所需）。  
   - 生成后**立即复制** token（页面关闭后不可再查看）。  
   - 若环境只允许 **Classic token**：新建时勾选 **`repo`**（权限更大，仅作备选）。

2. **写入仓库 Secret**  
   - 网页：**Settings → Secrets and variables → Actions → New repository secret**。  
   - **Name**：必须是 **`AI_HARNESS_PUSH_TOKEN`**（与 workflow 一致）。  
   - **Secret**：粘贴 PAT。  
   - 或使用 GitHub CLI（**勿在聊天里发送密钥**；执行后按提示粘贴或从 stdin/文件读入）：  
     ```bash
     gh secret set AI_HARNESS_PUSH_TOKEN --repo YOUR_ORG/ai-harness-demo
     ```

3. **验证**  
   - 触发一次会 `git push` 的 harness（或 Re-run 失败作业后再推修复）；新 commit 上应自动出现下一轮 **AI Harness Demo / PR Karate Harness**。  
   - 若当前 PR 仍停在旧 SHA，可配合上文「空提交」或 **Run workflow** 先跑绿一次。

### 用 `gh` 建库并配置 OpenAI（勿在聊天里发送密钥）

1. 安装并登录 [GitHub CLI](https://cli.github.com/)：`gh auth login`
2. 在本目录创建并推送仓库（示例仓库名可改）：

   ```bash
   gh repo create YOUR_ORG/ai-harness-demo --public --source=. --remote=origin --push
   ```

3. **在 GitHub 上要配的内容**（按需要；CI 与工作流一致）：

   | 配置项 | 放哪里 | 含义 |
   |--------|--------|------|
   | `AI_HARNESS_PUSH_TOKEN` | **Secrets** | （**推荐**）Fine-grained PAT，本仓库 **Contents: Read and write**；机器人推送后再次触发 CI，避免 PR 卡在必选检查。详见上文 **配置 `AI_HARNESS_PUSH_TOKEN`**。 |
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
