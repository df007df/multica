---
name: issue-create-from-context
description: >-
  将对话上下文整理为需求说明，再通过 multica issue create 创建 Multica 任务
  （必须指定 --project；项目、优先级、负责人从上下文推断；默认 --status backlog 待规划）。
  在用户要求从对话创建任务/工单、把需求落到 Multica、或将规格/需求文档转成 issue 时使用。
---

# 从上下文创建 Multica Issue

将对话上下文（或已有需求文档）转为 **Multica issue**，使用本地已安装的 `multica` CLI。**不要**使用 HTTP API 或 UI，除非 CLI 失败且用户要求备用方案。

## 硬规则：`--project` 必填

**未解析出 `--project <project-uuid>` 时，禁止执行 `multica issue create`，直接结束本 skill 流程。**

- 向用户说明：**缺少项目，无法创建 issue**（可列出 `multica project list` 结果供选择）。
- **不要**用「无项目」创建 issue，也不要猜测或省略 `--project`。
- 用户明确说「不要项目」时，仍须先确认：是否改为指定某个默认项目；未确认前不创建。

## 前置条件

创建前先执行：

```bash
multica auth status
multica workspace list
```

- 用户须已登录（否则执行 `multica login`）。
- 须已设置默认工作区（缺失则 `multica workspace switch <slug|id>`）。
- 假定 `multica` 在 `PATH` 中（用户已确认本地安装）。若 `command not found`，停止并提示安装或修复 `PATH`。

## 工作流

复制并跟踪进度：

```
- [ ] 1. 确定需求正文
- [ ] 2. 解析 --project（无则停止，不进入步骤 4）
- [ ] 3. 收集其余 issue 字段
- [ ] 4. 确认缺失字段（仅在不明确时）
- [ ] 5. 执行 multica issue create（必须带 --project）
- [ ] 6. 汇报执行结果
```

### 1. 确定需求正文

**若本线程已有需求/规格文档**（用户粘贴、agent 写了 `requirements.md`、计划文档、PRD 章节等）：

- **直接沿用**作为 `--title` 与 `--description`（必要时从文档提取简洁标题）。
- **不要**再向用户反复追问，除非 **项目** 或标题仍无法确定（见步骤 2、4）。

**否则：**

1. 用 2–4 条要点简要概括当前理解。
2. 提**一个**聚焦问题以锁定需求，例如：
   - 「应创建到哪个项目？工单标题与验收标准是什么？」
   - 或：「确认：在项目 \<名称\> 下创建 issue，标题为 \<一行目标\>？」
3. 在用户确认后再执行 CLI（除非用户已说「直接创建」/「go ahead」，且 **项目已明确**）。

### 2. 解析 `--project`（门禁步骤）

**本步骤未通过 → 停止，不执行 `multica issue create`。**

1. 从上下文查找：用户说的项目名、文档中的 `project` / `项目`、已有 issue 的 `project_id`、打开文件路径中的项目线索。
2. 若已有 UUID → 记为 `--project <uuid>`，进入步骤 3。
3. 若仅有名称或不确定 → 执行：

```bash
multica project list --output json
```

4. 匹配规则：
   - **唯一匹配** → 使用该项目的 `id`。
   - **多个匹配** → 用 `AskQuestion` 或一条消息让用户选定；**不要**擅自选一个。
   - **零匹配** → 停止；请用户给出项目名或 UUID，或先在工作区创建项目。

### 3. 从上下文收集其余 issue 字段

| 字段 | CLI 参数 | 来源提示 |
|------|----------|----------|
| 项目 | `--project`（**必填，步骤 2 已解析**） | 不得留空 |
| 标题 | `--title`（必填） | 用户诉求、规格标题、需求首行 |
| 描述 | `--description`、`--description-file` 或 `--description-stdin` | 完整规格、验收标准、链接 |
| 优先级 | `--priority` | 用户表述：urgent/high/medium/low/none |
| 状态 | `--status` | 默认 `backlog`（待规划）；用户指定其他阶段时用对应值 |
| 负责人 | `--assignee` 或 `--assignee-id` | 上下文中提到的 agent/成员/小组 |
| 父任务 | `--parent` | 已有 issue 的 key/UUID 的子任务 |
| 截止日期 | `--due-date` | 用户给出日期时用 RFC3339 |

**设置参数时的合法取值：**

- **优先级：** `none`、`low`、`medium`、`high`、`urgent`
- **状态：** `backlog`（待规划，**默认**）、`todo`、`in_progress`、`in_review`、`done`、`blocked`、`cancelled`

**负责人解析（可选）：**

```bash
multica workspace member list --output json
multica agent list --output json
```

若已知 UUID（脚本、先前 JSON 输出），优先使用 `--assignee-id <uuid>`。

### 4. 确认缺失字段（仅在不明确时）

**项目已在步骤 2 锁定，此处不再询问项目。**

**仅**对无法有把握推断的字段询问用户：

- **优先级** — 未说明且团队无合理默认
- **标题** — 步骤 1 后仍含糊

有 `AskQuestion` 时使用；否则在对话中询问。可选字段（负责人、截止日期、父任务）除非用户明确要求，否则不要阻塞。

**用户不在意时的默认：**

- 优先级：省略参数（服务端默认），或工作明显重要时用 `medium` — 说明你的选择。
- 状态：**始终** `--status backlog`（待规划）。从上下文新建的规格/issue 尚未排期，不应默认进入 `todo` 触发 agent。用户明确要求其他阶段时再改。

### 5. 执行 `multica issue create`

**再次确认：** 命令中必须包含 `--project "<已解析的 uuid>"`。缺则中止，不执行。

用显式参数构建命令。解析输出时始终加 `--output json`。

**短描述：**

```bash
multica issue create \
  --title "简洁的 issue 标题" \
  --project "<project-uuid>" \
  --description "验收标准与背景..." \
  --status backlog \
  --priority medium \
  --output json
```

**长描述（规格文档优先）：**

```bash
multica issue create \
  --title "..." \
  --project "<project-uuid>" \
  --description-file /tmp/multica-issue-desc.md \
  --status backlog \
  --priority high \
  --output json
```

**指定负责人时也要保留 `--project`：**

```bash
multica issue create \
  --title "..." \
  --project "<project-uuid>" \
  --assignee-id "<uuid>" \
  --status backlog \
  --output json
```

**规则：**

- 通过 Shell 执行；记录 **stdout**、**stderr**、**退出码**。
- 失败时未经用户同意**不要**重试（可能重复创建 issue）。
- **不要**向 `--attachment` 传入 `http(s)://` URL（仅本地路径）。
- 标题/描述中的 shell 元字符需转义，或使用 `--description-file`。

### 6. 汇报执行结果

结束时必须向用户提供结构化状态块。

**因缺少项目而停止（未执行 create）：**

```markdown
## Issue 创建 — 已中止

| 字段 | 值 |
|------|-----|
| 状态 | aborted |
| 原因 | 未指定或无法解析 `--project` |

**说明：**（简述上下文里缺什么；若已跑 `project list`，可列出可选项目名/id）

**下一步：** 请指定项目名或 UUID，或先在工作区创建项目后再试。
```

**成功（退出码 0）：** 从 JSON 解析 `identifier`（如 `MUL-123`）、`id`、`title`、`status`、`priority`、`project_id`。

```markdown
## Issue 创建 — 成功

| 字段 | 值 |
|------|-----|
| 状态 | created |
| 编号 | MUL-42 |
| ID | `<uuid>` |
| 标题 | ... |
| 项目 | `<project-uuid>` 或名称 |
| 优先级 | medium |
| 阶段 | backlog（待规划） |

**命令：** `multica issue create ...`（过长则缩写）

**CLI 输出：**（关键 JSON 字段；内容少时可附完整 JSON）
```

**失败（非零退出码）：**

```markdown
## Issue 创建 — 失败

| 字段 | 值 |
|------|-----|
| 状态 | failed |
| 退出码 | 1 |
| 错误 | <stderr 或 API 错误信息> |

**可能原因：**（认证 / 工作区 / 校验 / 重复 — 根据报文推断）

**下一步：**（一条具体修复，如 `multica login`、`multica workspace switch foo`、修正 `--project` id）
```

## 边界情况

| 情况 | 处理 |
|------|------|
| 无法确定项目 | **中止**；返回「已中止」状态块，不执行 `issue create` |
| 检测到重复 issue | 报文提及 duplicate；使用 `--allow-duplicate` 前先问用户 |
| 工作区错误 | `multica workspace list` → `multica workspace switch <slug>` → 最多重试一次 |
| `multica` 不在 PATH | 报告；建议在仓库执行 `make cli` 或安装脚本 |
| 用户只要草稿规格、不创建 | 步骤 1 后停止；不执行 CLI |
| 需要多个 issue | 每个 issue **各自**解析 `--project`；经用户确认后单独创建 |

## 示例

上下文：用户完成 Gitee webhook 文档；要在项目「Platform」创建 issue，优先级 high。

```bash
multica project list --output json   # 解析「Platform」→ UUID
multica issue create \
  --title "Document Gitee webhook setup" \
  --project "<uuid-from-list>" \
  --description-file ./requirements-gitee.md \
  --status backlog \
  --priority high \
  --output json
```

然后返回带 JSON 中 `MUL-*` 的**成功**状态表。
