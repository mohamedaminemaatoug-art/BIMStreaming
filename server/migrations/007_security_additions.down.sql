DROP TABLE IF EXISTS trusted_devices;
DROP TABLE IF EXISTS login_history;
DROP TABLE IF EXISTS audit_logs;

ALTER TABLE users
  DROP COLUMN IF EXISTS ban_reason,
  DROP COLUMN IF EXISTS is_banned,
  DROP COLUMN IF EXISTS last_failed_login_at,
  DROP COLUMN IF EXISTS failed_login_count,
  DROP COLUMN IF EXISTS locked_until;