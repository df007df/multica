-- Gitee OAuth integration: connected accounts, mirrored PR state,
-- and a Gitee-specific issue↔PR link table.

-- Stores Gitee OAuth connections per workspace. Multiple users may
-- connect their individual Gitee accounts to the same workspace.
CREATE TABLE gitee_connection (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id     UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    gitee_user_id    TEXT NOT NULL,
    gitee_login      TEXT NOT NULL,
    gitee_avatar_url TEXT,
    access_token     TEXT NOT NULL,
    refresh_token    TEXT,
    token_expires_at TIMESTAMPTZ,
    connected_by_id  UUID REFERENCES "user"(id) ON DELETE SET NULL,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, gitee_user_id)
);

CREATE INDEX idx_gitee_connection_workspace ON gitee_connection(workspace_id);

-- Mirrors github_pull_request but without GitHub-specific columns
-- (installation_id, head_sha, mergeable_state) and without a check_suite
-- child table (Gitee does not expose CI check suites via webhooks).
CREATE TABLE gitee_pull_request (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    workspace_id       UUID NOT NULL REFERENCES workspace(id) ON DELETE CASCADE,
    gitee_connection_id UUID NOT NULL REFERENCES gitee_connection(id) ON DELETE CASCADE,
    repo_owner         TEXT NOT NULL,
    repo_name          TEXT NOT NULL,
    pr_number          INTEGER NOT NULL,
    title              TEXT NOT NULL,
    state              TEXT NOT NULL CHECK (state IN ('open', 'closed', 'merged')),
    html_url           TEXT NOT NULL,
    branch             TEXT,
    author_login       TEXT,
    author_avatar_url  TEXT,
    merged_at          TIMESTAMPTZ,
    closed_at          TIMESTAMPTZ,
    pr_created_at      TIMESTAMPTZ NOT NULL,
    pr_updated_at      TIMESTAMPTZ NOT NULL,
    additions          INTEGER NOT NULL DEFAULT 0,
    deletions          INTEGER NOT NULL DEFAULT 0,
    changed_files      INTEGER NOT NULL DEFAULT 0,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, repo_owner, repo_name, pr_number)
);

CREATE INDEX idx_gitee_pull_request_workspace ON gitee_pull_request(workspace_id);

-- Issue↔PR link table for Gitee PRs. Parallel to issue_pull_request for
-- GitHub PRs, kept separate because pull_request_id references a different
-- FK table (gitee_pull_request vs github_pull_request).
CREATE TABLE issue_gitee_pull_request (
    issue_id        UUID NOT NULL REFERENCES issue(id) ON DELETE CASCADE,
    pull_request_id UUID NOT NULL REFERENCES gitee_pull_request(id) ON DELETE CASCADE,
    linked_by_type  TEXT,
    linked_by_id    UUID,
    linked_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (issue_id, pull_request_id)
);

CREATE INDEX idx_issue_gitee_pr_pr ON issue_gitee_pull_request(pull_request_id);
