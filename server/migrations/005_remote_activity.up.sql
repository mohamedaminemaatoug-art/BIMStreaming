CREATE TABLE IF NOT EXISTS remote_session_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_device_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
  session_token TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS activity_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_username TEXT NOT NULL,
  target_device_id TEXT NOT NULL,
  session_type TEXT NOT NULL CHECK (session_type IN ('control', 'file_transfer', 'view_only')),
  duration_seconds INTEGER,
  status TEXT NOT NULL CHECK (status IN ('success', 'disconnected', 'failed')),
  started_at TIMESTAMPTZ NOT NULL,
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_activity_log_user_started ON activity_log(user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_remote_invites_target_status_expires
ON remote_session_invites(target_device_id, status, expires_at);

DROP TRIGGER IF EXISTS trg_remote_session_invites_updated_at ON remote_session_invites;
CREATE TRIGGER trg_remote_session_invites_updated_at BEFORE UPDATE ON remote_session_invites FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_activity_log_updated_at ON activity_log;
CREATE TRIGGER trg_activity_log_updated_at BEFORE UPDATE ON activity_log FOR EACH ROW EXECUTE FUNCTION set_updated_at();
