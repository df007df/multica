# 示例：Agent Plan 可见性讨论中的浓缩写法

用作质量参考，勿照搬范围。

## 问题写法示例
- 供应商特有模式（Claude plan）在**平台外**产出产物（`~/.claude/plans/`）。
- UI 只显示工具名/短摘要；完整内容藏在 transcript 折叠里。
- Multica 内无审批路径（daemon 为非交互式）。

## 现状表写法示例
| 能力 | 现状 |
|------|------|
| task_message | 完整流已持久化 |
| Plan 文件 | 仅在 daemon 宿主机 |
| UI | 仅 transcript 图标；无 Plan 入口 |

## 推荐方案写法示例
在事件流中检测 → 经**用户可见通道**投递（评论）→ 在 `agent_task_queue` 上挂元数据供深链。

## 风险表写法示例
| 风险 | 缓解 |
|------|------|
| 重复评论（daemon + agent + CompleteTask） | 幂等 FR；HasAgentCommentedSince 策略 |
| 读文件竞态 | 优先使用流内 `plan` 正文 |
| @ 提及触发副作用 | 去掉 @mention 或跳过入队 |

## 待决问题写法示例
- Plan 评论是否算作「agent 已评论」以参与合成？
- Chat 类任务是否纳入范围？
- Plan 发帖是否发 Inbox 通知？
