CREATE TABLE IF NOT EXISTS data_export_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'ready', 'failed')),
  download_url TEXT,
  ready_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS account_deletion_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requested_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason TEXT,
  status TEXT NOT NULL CHECK (status IN ('pending', 'scheduled', 'cancelled', 'processed')),
  scheduled_for TIMESTAMPTZ NOT NULL,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_account_deletion_active_user
ON account_deletion_requests (user_id)
WHERE status IN ('pending', 'scheduled');

CREATE INDEX IF NOT EXISTS idx_data_export_requests_user_created
ON data_export_requests(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_account_deletion_user_created
ON account_deletion_requests(user_id, created_at DESC);

DROP TRIGGER IF EXISTS trg_data_export_requests_updated_at ON data_export_requests;
CREATE TRIGGER trg_data_export_requests_updated_at BEFORE UPDATE ON data_export_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_account_deletion_requests_updated_at ON account_deletion_requests;
CREATE TRIGGER trg_account_deletion_requests_updated_at BEFORE UPDATE ON account_deletion_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();
