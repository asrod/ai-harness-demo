# 本 PR 在演示什么？

故意把 `/hello` 的 JSON 改成 `message: 'wrong'`，与 Karate 契约不一致。

**打开本仓库的 Actions 标签页**，找到本次 PR 触发的 **AI Harness Demo** 工作流日志，你会看到：

1. 首轮测试失败  
2. **AI 修复阶段**横幅 → LLM 或 mock 改写 `app/server.js`  
3. **unified diff** 与修复后的 **curl /hello**  
4. 复测通过  
5. 工作流会向 **本分支再推一个 commit**（`fix(hello): AI harness repair…`），PR 上出现第二条提交

合并前请确认：第二条提交已把接口恢复为契约要求的 `world`。
