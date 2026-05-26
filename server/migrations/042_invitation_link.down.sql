DROP INDEX IF EXISTS idx_invitation_link_pending;
ALTER TABLE workspace_invitation ALTER COLUMN invitee_email SET NOT NULL;
ALTER TABLE workspace_invitation DROP COLUMN IF EXISTS invite_type;
