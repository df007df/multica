-- =====================
-- Gitee OAuth Connection
-- =====================

-- name: ListGiteeConnectionsByWorkspace :many
SELECT * FROM gitee_connection
WHERE workspace_id = $1
ORDER BY created_at ASC;

-- name: GetGiteeConnectionByWorkspaceAndUserID :one
SELECT * FROM gitee_connection
WHERE workspace_id = $1 AND gitee_user_id = $2;

-- name: GetGiteeConnectionByID :one
SELECT * FROM gitee_connection
WHERE id = $1;

-- name: CreateGiteeConnection :one
INSERT INTO gitee_connection (
    workspace_id, gitee_user_id, gitee_login, gitee_avatar_url,
    access_token, refresh_token, token_expires_at, connected_by_id
) VALUES (
    $1, $2, $3, sqlc.narg('gitee_avatar_url'),
    $4, sqlc.narg('refresh_token'), sqlc.narg('token_expires_at'),
    sqlc.narg('connected_by_id')
)
ON CONFLICT (workspace_id, gitee_user_id) DO UPDATE SET
    gitee_login = EXCLUDED.gitee_login,
    gitee_avatar_url = EXCLUDED.gitee_avatar_url,
    access_token = EXCLUDED.access_token,
    refresh_token = EXCLUDED.refresh_token,
    token_expires_at = EXCLUDED.token_expires_at,
    updated_at = now()
RETURNING *;

-- name: DeleteGiteeConnection :exec
DELETE FROM gitee_connection WHERE id = $1 AND workspace_id = $2;

-- name: DeleteGiteeConnectionByWorkspaceAndUserID :one
DELETE FROM gitee_connection
WHERE workspace_id = $1 AND gitee_user_id = $2
RETURNING id, workspace_id;

-- name: ListAllGiteeConnections :many
SELECT * FROM gitee_connection;

-- =====================
-- Gitee Pull Request
-- =====================

-- name: UpsertGiteePullRequest :one
INSERT INTO gitee_pull_request (
    workspace_id, repo_owner, repo_name, pr_number,
    title, state, html_url, branch, author_login, author_avatar_url,
    merged_at, closed_at, pr_created_at, pr_updated_at,
    additions, deletions, changed_files
) VALUES (
    $1, $2, $3, $4,
    $5, $6, $7, sqlc.narg('branch'), sqlc.narg('author_login'), sqlc.narg('author_avatar_url'),
    sqlc.narg('merged_at'), sqlc.narg('closed_at'), $8, $9,
    $10, $11, $12
)
ON CONFLICT (workspace_id, repo_owner, repo_name, pr_number) DO UPDATE SET
    title = EXCLUDED.title,
    state = EXCLUDED.state,
    html_url = EXCLUDED.html_url,
    branch = EXCLUDED.branch,
    author_login = EXCLUDED.author_login,
    author_avatar_url = EXCLUDED.author_avatar_url,
    merged_at = EXCLUDED.merged_at,
    closed_at = EXCLUDED.closed_at,
    pr_updated_at = EXCLUDED.pr_updated_at,
    additions = EXCLUDED.additions,
    deletions = EXCLUDED.deletions,
    changed_files = EXCLUDED.changed_files,
    updated_at = now()
RETURNING *;

-- name: GetGiteePullRequest :one
SELECT * FROM gitee_pull_request
WHERE workspace_id = $1 AND repo_owner = $2 AND repo_name = $3 AND pr_number = $4;

-- name: ListGiteePullRequestsByIssue :many
SELECT
    pr.id, pr.workspace_id, pr.repo_owner, pr.repo_name,
    pr.pr_number, pr.title, pr.state, pr.html_url, pr.branch, pr.author_login,
    pr.author_avatar_url, pr.merged_at, pr.closed_at, pr.pr_created_at,
    pr.pr_updated_at, pr.additions, pr.deletions, pr.changed_files,
    pr.created_at, pr.updated_at
FROM gitee_pull_request pr
JOIN issue_gitee_pull_request igpr ON igpr.pull_request_id = pr.id
WHERE igpr.issue_id = sqlc.arg('issue_id')
ORDER BY pr.pr_created_at DESC;

-- name: ListIssueIDsForGiteePullRequest :many
SELECT issue_id FROM issue_gitee_pull_request
WHERE pull_request_id = $1;

-- name: GetSiblingGiteePullRequestStateCountsForIssue :one
SELECT
    COALESCE(SUM(CASE WHEN pr.state = 'open' THEN 1 ELSE 0 END), 0)::bigint AS open_count,
    COALESCE(SUM(CASE WHEN pr.state = 'merged' THEN 1 ELSE 0 END), 0)::bigint AS merged_count
FROM gitee_pull_request pr
JOIN issue_gitee_pull_request igpr ON igpr.pull_request_id = pr.id
WHERE igpr.issue_id = $1
  AND pr.id <> $2;

-- =====================
-- Issue ↔ Gitee PR link
-- =====================

-- name: LinkIssueToGiteePullRequest :exec
INSERT INTO issue_gitee_pull_request (
    issue_id, pull_request_id, linked_by_type, linked_by_id
) VALUES (
    $1, $2, sqlc.narg('linked_by_type'), sqlc.narg('linked_by_id')
)
ON CONFLICT (issue_id, pull_request_id) DO NOTHING;

-- name: UnlinkIssueFromGiteePullRequest :exec
DELETE FROM issue_gitee_pull_request
WHERE issue_id = $1 AND pull_request_id = $2;
