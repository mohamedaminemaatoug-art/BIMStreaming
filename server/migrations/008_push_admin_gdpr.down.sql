DROP TRIGGER IF EXISTS trg_account_deletion_requests_updated_at ON account_deletion_requests;
DROP TRIGGER IF EXISTS trg_data_export_requests_updated_at ON data_export_requests;

DROP INDEX IF EXISTS idx_account_deletion_user_created;
DROP INDEX IF EXISTS idx_data_export_requests_user_created;
DROP INDEX IF EXISTS idx_account_deletion_active_user;

DROP TABLE IF EXISTS account_deletion_requests;
DROP TABLE IF EXISTS data_export_requests;
