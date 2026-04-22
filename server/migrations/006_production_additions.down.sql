DROP TABLE IF EXISTS push_tokens;
DROP TABLE IF EXISTS user_subscriptions;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS message_attachments;
DROP TABLE IF EXISTS message_reactions;
DROP TABLE IF EXISTS community_audit_log;
DROP TABLE IF EXISTS community_bans;
DROP TABLE IF EXISTS community_invites;
DROP TABLE IF EXISTS community_announcements;
DROP TABLE IF EXISTS unattended_access;
DROP TABLE IF EXISTS session_permissions;
DROP TABLE IF EXISTS remote_sessions;
DROP TABLE IF EXISTS user_status;
DROP TABLE IF EXISTS trusted_devices;
DROP TABLE IF EXISTS login_history;
DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS totp_backup_codes;

ALTER TABLE community_messages
  DROP COLUMN IF EXISTS is_deleted,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS is_edited,
  DROP COLUMN IF EXISTS reply_to_id;

ALTER TABLE direct_messages
  DROP COLUMN IF EXISTS is_deleted,
  DROP COLUMN IF EXISTS edited_at,
  DROP COLUMN IF EXISTS is_edited,
  DROP COLUMN IF EXISTS reply_to_id;

ALTER TABLE users
  DROP CONSTRAINT IF EXISTS chk_users_theme,
  DROP COLUMN IF EXISTS is_superadmin,
  DROP COLUMN IF EXISTS device_alias,
  DROP COLUMN IF EXISTS two_factor_secret,
  DROP COLUMN IF EXISTS two_factor_enabled,
  DROP COLUMN IF EXISTS notification_preferences,
  DROP COLUMN IF EXISTS theme,
  DROP COLUMN IF EXISTS timezone,
  DROP COLUMN IF EXISTS language,
  DROP COLUMN IF EXISTS display_name;