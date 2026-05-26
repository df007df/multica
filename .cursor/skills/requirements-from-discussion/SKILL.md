---
name: requirements-from-discussion
description: >-
  将已完成的技术设计讨论整理为结构化产品需求文档（PRD）。
  在用户要求把对话总结为需求文档、PRD、需求说明、功能规格，
  或说「把讨论整理成需求」，且已探讨架构、缺口、风险与实现方案时使用。
---

# 从讨论生成需求文档

根据**当前对话**（及可选的代码库事实）生成**产品需求文档（PRD）**。输出可直接粘贴到 Linear、Notion、GitHub Issue 或 `apps/docs/`。

## 何时使用

- 用户明确要求：需求文档 / PRD / 需求说明 / 功能规格。
- 设计讨论**已结束**（问题、方案、风险已探讨），需要**正式成文**。
- 用户说「把上面的讨论总结成需求」或类似表述。

**不要**用于：纯编码任务、单行修复、或仅作 API 参考的文档。

## 工作流

### 1. 挖掘对话内容

提取并分类：

| 类别 | 需捕获内容 |
|------|------------|
| **问题** | 用户可见痛点、示例、讨论中提到的截图/日志片段 |
| **现状** | 当前产品形态 + 代码现状（若已核实） |
| **约束** | 架构规则、非目标、供应商/平台限制 |
| **讨论过的方案** | 各方案及用户/agent 权衡过的利弊 |
| **推荐方向** | 倾向方案及理由 |
| **风险** | 重复、竞态、安全、UX 混淆、触发循环等 |
| **待决问题** | 仍须 PM/工程拍板的事项 |

若讨论中对代码库有假设，在写「现状」前须用**定向搜索/阅读**核实。

### 2. 划定范围

- **范围内** → 目标 + 功能需求（FR-x）。
- **范围外** → 非目标（明确列出延后项）。
- **边界** → 聊天 vs Issue、Web vs 移动端、哪个 provider/runtime。

### 3. 起草文档

遵循 [template.md](template.md)。使用**与用户请求相同的语言**（用户用中文则用中文）。

规则：

- **声明式需求** — 可验证、编号 `FR-n`。
- **分节清晰** —「现状 / 目标 / 方案 / 风险 / 待决」分开写，不要把风险埋在 FR 正文里。
- **引用代码** — 核实后写路径（如 `server/pkg/agent/claude.go`），避免笼统的「后端」。
- **PRD 中不写实现代码**，除非用户要求伪 API 形态或 schema 草图。
- 文末必须有**待决问题** — 对话中未定的产品选择全部列出。

### 4. 质量自检

返回前核对：

- [ ] 未参与讨论的人能看懂问题与预期方案。
- [ ] 每条 FR 有明确主体（用户 / daemon / server / UI）。
- [ ] 风险附有**缓解措施**或对应 FR。
- [ ] 验收标准与 FR 可对应。
- [ ] 非目标能防止范围蔓延。
- [ ] 若有延后的产品选择，待决一节非空。

## 分析逻辑（技术类功能）

话题涉及 **Agent、Daemon、集成或异步任务** 时，使用以下清单：

```
1. 数据链路
   内容在哪产生？→ 持久化什么？→ UI 读什么？

2. 投递路径
   谁产出产物（agent CLI / daemon / server job）？
   Web 是否无需新 API 即可访问？

3. 交互模型
   交互式还是无头？是否需要 stdin/WS/控制通道？
   是否依赖特定供应商（如 Claude plan mode）？

4. 幂等与重复
   同一事件触发两次？agent 与平台是否都在做同一动作？

5. 对现有流程的副作用
   评论 → on_comment 队列？HasXSince 标志？通知？
   CompleteTask 合成？会话恢复？

6. UI 可发现性
   现有入口（transcript、execution log）vs 新入口 — 缺口须写清。

7. 分期
   MVP = 最小用户价值；V1.1 = 打磨；V2 = 其他端（聊天、移动端等）。
```

## 输出约定

- **一份** Markdown，顶级标题 `# <功能名> — 需求说明`（用户要英文则用英文等价标题）。
- 章节顺序与 template 一致；可选 §11 参考（实现锚点），附调查得到的文件路径。
- 页脚：`文档版本：基于 <date> 讨论整理；实现前需对第 N 节待决项确认。`

## Multica 单体仓库提示

讨论与本仓库相关时，优先对照以下锚点（须核实，勿臆测）：

| 主题 | 查阅位置 |
|------|----------|
| Agent 执行 / daemon | `server/internal/daemon/`、`server/pkg/agent/` |
| 任务消息 | `task_message`、`ReportTaskMessages`、`listTaskMessages` |
| 评论 / 合成 | `server/internal/service/task.go`（`createAgentComment`、`CompleteTask`） |
| Issue UI | `packages/views/issues/`（`execution-log-section`、`agent-live-card`） |
| Transcript | `packages/views/common/task-transcript/` |
| Agent CLI | `server/cmd/multica/cmd_issue.go`（`issue comment add`） |

## 示例触发语

用户：「把上面的讨论总结成一个需求内容，返回给我」  
→ 走完整工作流 + [template.md](template.md)。

用户：「生成 PRD，英文」  
→ 同样结构，正文用英文。

## 延伸阅读

- 完整章节模板：[template.md](template.md)
- 示例（Agent Plan 可见性）：[example-agent-plan.md](example-agent-plan.md)
