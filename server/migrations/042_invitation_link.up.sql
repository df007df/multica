ALTER TABLE workspace_invitation ALTER COLUMN invitee_email DROP NOT NULL;
ALTER TABLE workspace_invitation ADD COLUMN IF NOT EXISTS invite_type TEXT NOT NULL DEFAULT 'email' CHECK (invite_type IN ('email', 'link'));
CREATE INDEX IF NOT EXISTS idx_invitation_link_pending ON workspace_invitation(workspace_id) WHERE status = 'pending' AND invite_type = 'link';
