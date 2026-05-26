ALTER TABLE "user" ADD COLUMN IF NOT EXISTS dingtalk_id TEXT UNIQUE;
CREATE INDEX IF NOT EXISTS idx_user_dingtalk_id ON "user"(dingtalk_id);
