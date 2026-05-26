DROP INDEX IF EXISTS idx_user_dingtalk_id;
ALTER TABLE "user" DROP COLUMN IF EXISTS dingtalk_id;
