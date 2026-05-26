---
name: branch-commit-pr
description: >-
  将当前改动整理为功能分支、按规范提交、推送并针对 feature/dev 开 PR。
  在用户要求提交并开 PR、交付改动、提交评审、推送分支或合并到 feature/dev 时使用。
---

# 分支、提交、推送、PR

在**新的主题分支**上交付本地工作并打开 PR。**默认合并目标：`feature/dev`**，除非用户指定其他目标（如 `main`）。

## 受保护分支（禁止直接提交）

未经用户明确同意，**不要**在以下分支上保留改动或直接推送提交：

| 分支 | 原因 |
|------|------|
| `main`、`master` | 生产 / 默认分支 |
| `feature/dev` | 团队集成分支 |
| `develop`、`staging`、`production` | 常见稳定分支名 |
| `release/*`、`hotfix/*` | 发布线 |

若当前在受保护分支上，提交前须先创建新分支（见步骤 2）。

## 工作流

复制并跟踪进度：

```
- [ ] 1. 检查状态
- [ ] 2. 创建主题分支（如需要）
- [ ] 3. 提交
- [ ] 4. 推送
- [ ] 5. 开 PR → feature/dev
```

### 1. 检查状态

并行执行：

```bash
git status
git diff
git diff --staged
git branch --show-current
git log -5 --oneline
```

- 概括改动内容，确定**一条**符合规范的提交信息（或询问是否应拆成多次提交）。
- **不要**提交 `.env`、凭据或其他密钥；若存在则警告用户。
- 若无内容可提交且分支已推送，跳到步骤 5。

### 2. 创建主题分支

若已在非受保护的主题分支上**且**用户未要求新分支，**跳过**本步。

否则从当前 HEAD 创建（保留工作区改动）：

```bash
git switch -c <type>/<short-slug>
```

分支命名（与仓库风格一致）：

| 改动类型 | 前缀 | 示例 |
|----------|------|------|
| 功能 | `feat/` | `feat/gitee-webhook-retry` |
| 缺陷修复 | `fix/` | `fix/login-redirect-loop` |
| 杂项 / 工具 | `chore/` | `chore/ignore-next-env-dts` |
| 重构 | `refactor/` | `refactor/issue-query-keys` |
| 仅文档 | `docs/` | `docs/github-integration` |
| 仅测试 | `test/` | `test/inbox-pagination` |

使用小写、连字符、简短 slug（≤4 个词）。再次确认：分支名**不得**为受保护分支。

### 3. 提交

遵循仓库 **Conventional Commits**：`feat(scope)`、`fix(scope)`、`refactor(scope)`、`docs`、`test(scope)`、`chore(scope)`。

1. 仅暂存相关文件（不含密钥）。
2. 提交信息写**原因**，不要罗列文件；正文 1–2 句即可。
3. 使用 HEREDOC 提交：

```bash
git add <paths...>
git commit -m "$(cat <<'EOF'
<type>(<scope>): <summary>

<optional body>
EOF
)"
git status
```

**Git 安全：** 禁止 `git config`；除非用户要求否则禁止 `--no-verify`；禁止对 `main`/`master`/`feature/dev` 强制推送；除非用户明确要求且 HEAD 为未推送的本地提交，否则禁止 amend。

### 4. 推送

```bash
git push -u origin HEAD
```

若推送被拒绝（非快进），报告并询问用户——除非用户明确要求，否则不要 force-push。

### 5. 打开 PR

**基准分支：** `feature/dev`（默认）。仅当用户指定其他基准时覆盖（如 `--base main`）。

```bash
gh pr create --base feature/dev --title "<与提交主题相同或更清晰的标题>" --body "$(cat <<'EOF'
## 摘要
- <要点：改了什么、为什么>

## 测试计划
- [ ] <评审人如何验证>
EOF
)"
```

将 **PR URL** 返回给用户。

## 边界情况

| 情况 | 处理 |
|------|------|
| 在 `feature/dev` 上有本地提交 | 从当前 HEAD 建主题分支，再推送并开 PR |
| 受保护分支上有未提交改动 | `git switch -c <branch>`（改动会带走），再提交 |
| 多块不相关改动 | 建议拆分；若用户要多个 PR，使用 `split-to-prs` 技能 |
| 用户说「不要 PR」/「只提交」 | 在步骤 3 或 4 后停止 |
| 用户指定其他基准分支 | `gh pr create --base <branch>` |
| `gh` 未认证 | 报告阻塞；用户需执行 `gh auth login` |

## 示例

用户在 `feature/dev` 上已暂存修复：

```bash
git switch -c fix/inbox-mark-read
git commit -m "$(cat <<'EOF'
fix(inbox): mark thread read on open

Invalidate inbox query after PATCH so badge clears without refresh.
EOF
)"
git push -u origin HEAD
gh pr create --base feature/dev --title "fix(inbox): mark thread read on open" --body "..."
```
