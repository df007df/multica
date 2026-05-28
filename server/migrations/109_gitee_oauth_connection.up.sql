-- Gitee OAuth connections per workspace. Multiple users may connect
-- their individual Gitee accounts to the same workspace. The daemon
-- uses the first available connection's access token to clone private
-- Gitee repos for agent tasks.
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
