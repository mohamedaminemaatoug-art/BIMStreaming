ALTER TABLE users
  ADD COLUMN IF NOT EXISTS display_name TEXT,
  ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC',
  ADD COLUMN IF NOT EXISTS theme TEXT NOT NULL DEFAULT 'dark',
  ADD COLUMN IF NOT EXISTS notification_preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS two_factor_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS two_factor_secret TEXT,
  ADD COLUMN IF NOT EXISTS device_alias TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS is_superadmin BOOLEAN NOT NULL DEFAULT FALSE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_users_theme'
  ) THEN
    ALTER TABLE users ADD CONSTRAINT chk_users_theme CHECK (theme IN ('dark', 'light', 'system'));
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS totp_backup_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_hash TEXT NOT NULL,
  used_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  resource_type TEXT,
  resource_id TEXT,
  ip_address TEXT,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS login_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ip_address TEXT,
  country TEXT,
  city TEXT,
  device_fingerprint TEXT,
  os TEXT,
  app_version TEXT,
  status TEXT NOT NULL CHECK (status IN ('success', 'failed', 'blocked')),
  failure_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trusted_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_fingerprint TEXT NOT NULL,
  device_name TEXT,
  last_used_at TIMESTAMPTZ,
  trusted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_status (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT,
  message TEXT,
  availability TEXT NOT NULL DEFAULT 'available' CHECK (availability IN ('available', 'busy', 'away', 'do_not_disturb', 'invisible')),
  expires_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS remote_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invite_id UUID REFERENCES remote_session_invites(id) ON DELETE SET NULL,
  controller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  host_device_id TEXT NOT NULL,
  session_token TEXT NOT NULL UNIQUE,
  session_type TEXT NOT NULL CHECK (session_type IN ('control', 'view_only', 'file_transfer', 'presentation')),
  quality TEXT NOT NULL DEFAULT 'auto' CHECK (quality IN ('auto', 'low', 'medium', 'high', 'ultra')),
  encryption_type TEXT NOT NULL DEFAULT 'aes256',
  started_at TIMESTAMPTZ,
  ended_at TIMESTAMPTZ,
  duration_seconds INTEGER,
  end_reason TEXT CHECK (end_reason IN ('host_ended', 'controller_ended', 'timeout', 'connection_lost', 'kicked')),
  bytes_sent BIGINT NOT NULL DEFAULT 0,
  bytes_received BIGINT NOT NULL DEFAULT 0,
  avg_latency_ms INTEGER,
  recorded BOOLEAN NOT NULL DEFAULT FALSE,
  recording_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS session_permissions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL UNIQUE REFERENCES remote_sessions(id) ON DELETE CASCADE,
  allow_keyboard BOOLEAN NOT NULL DEFAULT TRUE,
  allow_mouse BOOLEAN NOT NULL DEFAULT TRUE,
  allow_clipboard BOOLEAN NOT NULL DEFAULT TRUE,
  allow_file_transfer BOOLEAN NOT NULL DEFAULT FALSE,
  allow_audio BOOLEAN NOT NULL DEFAULT FALSE,
  allow_restart BOOLEAN NOT NULL DEFAULT FALSE,
  allow_lock_screen BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS unattended_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  controller_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  access_password_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (host_user_id, controller_user_id)
);

CREATE TABLE IF NOT EXISTS community_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_invites (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code TEXT UNIQUE NOT NULL,
  max_uses INTEGER,
  uses_count INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_bans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  banned_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason TEXT,
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (community_id, user_id)
);

CREATE TABLE IF NOT EXISTS community_audit_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id UUID NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
  actor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  target_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS message_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL,
  message_type TEXT NOT NULL CHECK (message_type IN ('dm', 'community')),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (message_id, message_type, user_id, emoji)
);

CREATE TABLE IF NOT EXISTS message_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id UUID NOT NULL,
  message_type TEXT NOT NULL CHECK (message_type IN ('dm', 'community')),
  uploader_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,
  file_size_bytes BIGINT,
  mime_type TEXT,
  storage_url TEXT NOT NULL,
  thumbnail_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE direct_messages
  ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES direct_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_edited BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE community_messages
  ADD COLUMN IF NOT EXISTS reply_to_id UUID REFERENCES community_messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_edited BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  display_name TEXT,
  max_concurrent_sessions INTEGER,
  max_community_members INTEGER,
  max_communities INTEGER,
  unattended_access BOOLEAN NOT NULL DEFAULT FALSE,
  session_recording BOOLEAN NOT NULL DEFAULT FALSE,
  priority_support BOOLEAN NOT NULL DEFAULT FALSE,
  custom_alias BOOLEAN NOT NULL DEFAULT FALSE,
  price_monthly_usd NUMERIC(10,2),
  price_yearly_usd NUMERIC(10,2),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES plans(id),
  status TEXT NOT NULL CHECK (status IN ('active', 'cancelled', 'expired', 'trial', 'past_due')),
  billing_cycle TEXT CHECK (billing_cycle IN ('monthly', 'yearly')),
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  trial_end TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  external_subscription_id TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS push_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  platform TEXT NOT NULL CHECK (platform IN ('fcm', 'apns', 'web')),
  device_fingerprint TEXT,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS idx_totp_backup_codes_user_id ON totp_backup_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_user_created ON audit_logs(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_history_user_created ON login_history(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_trusted_devices_user_id ON trusted_devices(user_id);
CREATE INDEX IF NOT EXISTS idx_user_status_user_id ON user_status(user_id);
CREATE INDEX IF NOT EXISTS idx_remote_sessions_host_controller ON remote_sessions(host_id, controller_id);
CREATE INDEX IF NOT EXISTS idx_remote_sessions_token ON remote_sessions(session_token);
CREATE INDEX IF NOT EXISTS idx_session_permissions_session_id ON session_permissions(session_id);
CREATE INDEX IF NOT EXISTS idx_unattended_access_host_controller ON unattended_access(host_user_id, controller_user_id);
CREATE INDEX IF NOT EXISTS idx_community_announcements_community_created ON community_announcements(community_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_invites_community_active ON community_invites(community_id, is_active);
CREATE INDEX IF NOT EXISTS idx_community_bans_community_user ON community_bans(community_id, user_id);
CREATE INDEX IF NOT EXISTS idx_community_audit_log_community_created ON community_audit_log(community_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_message_reactions_message ON message_reactions(message_id, message_type);
CREATE INDEX IF NOT EXISTS idx_message_attachments_message ON message_attachments(message_id, message_type);
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_id ON user_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON push_tokens(user_id);

DROP TRIGGER IF EXISTS trg_trusted_devices_updated_at ON trusted_devices;
CREATE TRIGGER trg_trusted_devices_updated_at BEFORE UPDATE ON trusted_devices FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_user_status_updated_at ON user_status;
CREATE TRIGGER trg_user_status_updated_at BEFORE UPDATE ON user_status FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_remote_sessions_updated_at ON remote_sessions;
CREATE TRIGGER trg_remote_sessions_updated_at BEFORE UPDATE ON remote_sessions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_session_permissions_updated_at ON session_permissions;
CREATE TRIGGER trg_session_permissions_updated_at BEFORE UPDATE ON session_permissions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_unattended_access_updated_at ON unattended_access;
CREATE TRIGGER trg_unattended_access_updated_at BEFORE UPDATE ON unattended_access FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_community_announcements_updated_at ON community_announcements;
CREATE TRIGGER trg_community_announcements_updated_at BEFORE UPDATE ON community_announcements FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_user_subscriptions_updated_at ON user_subscriptions;
CREATE TRIGGER trg_user_subscriptions_updated_at BEFORE UPDATE ON user_subscriptions FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_push_tokens_updated_at ON push_tokens;
CREATE TRIGGER trg_push_tokens_updated_at BEFORE UPDATE ON push_tokens FOR EACH ROW EXECUTE FUNCTION set_updated_at();

INSERT INTO plans (name, display_name, max_concurrent_sessions, max_community_members, max_communities, unattended_access, session_recording, priority_support, custom_alias, price_monthly_usd, price_yearly_usd)
VALUES
  ('free', 'Free', 1, 10, 1, FALSE, FALSE, FALSE, FALSE, 0.00, 0.00),
  ('pro', 'Pro', 3, 100, 5, TRUE, TRUE, FALSE, TRUE, 12.00, 120.00),
  ('team', 'Team', 10, 1000, 20, TRUE, TRUE, TRUE, TRUE, 29.00, 290.00),
  ('enterprise', 'Enterprise', NULL, NULL, NULL, TRUE, TRUE, TRUE, TRUE, 99.00, 990.00)
ON CONFLICT (name) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  max_concurrent_sessions = EXCLUDED.max_concurrent_sessions,
  max_community_members = EXCLUDED.max_community_members,
  max_communities = EXCLUDED.max_communities,
  unattended_access = EXCLUDED.unattended_access,
  session_recording = EXCLUDED.session_recording,
  priority_support = EXCLUDED.priority_support,
  custom_alias = EXCLUDED.custom_alias,
  price_monthly_usd = EXCLUDED.price_monthly_usd,
  price_yearly_usd = EXCLUDED.price_yearly_usd;
