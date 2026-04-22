package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

type AuditFilters struct {
	UserID       *uuid.UUID
	Action       string
	ResourceType string
	DateFrom     *time.Time
	DateTo       *time.Time
}

func (r *Repository) CreateEmailVerification(ctx context.Context, userID uuid.UUID, token string, expiresAt time.Time) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO email_verifications (user_id, token, expires_at) VALUES ($1, $2, $3)`,
		userID, token, expiresAt,
	)
	return err
}

func (r *Repository) GetLatestEmailVerification(ctx context.Context, userID uuid.UUID, token string) (*models.EmailVerification, error) {
	var ver models.EmailVerification
	query := `
	SELECT * FROM email_verifications
	WHERE user_id=$1 AND token=$2
	ORDER BY created_at DESC
	LIMIT 1`
	if err := r.db.GetContext(ctx, &ver, query, userID, token); err != nil {
		return nil, err
	}
	return &ver, nil
}

func (r *Repository) MarkEmailVerificationUsed(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE email_verifications SET used_at=NOW(), updated_at=NOW() WHERE id=$1`, id)
	return err
}

func (r *Repository) MarkUserVerified(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET is_verified=true, updated_at=NOW() WHERE id=$1`, userID)
	return err
}

func (r *Repository) CreateRefreshToken(ctx context.Context, userID uuid.UUID, tokenHash string, deviceFingerprint string, expiresAt time.Time) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO refresh_tokens (user_id, token_hash, device_fingerprint, expires_at) VALUES ($1, $2, $3, $4)`,
		userID, tokenHash, nullableString(deviceFingerprint), expiresAt,
	)
	return err
}

func (r *Repository) GetRefreshToken(ctx context.Context, tokenHash string) (*models.RefreshToken, error) {
	var token models.RefreshToken
	query := `SELECT * FROM refresh_tokens WHERE token_hash=$1 AND revoked_at IS NULL LIMIT 1`
	if err := r.db.GetContext(ctx, &token, query, tokenHash); err != nil {
		return nil, err
	}
	return &token, nil
}

func (r *Repository) RevokeRefreshTokenByHash(ctx context.Context, tokenHash string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE refresh_tokens SET revoked_at=NOW(), updated_at=NOW() WHERE token_hash=$1`, tokenHash)
	return err
}

func (r *Repository) RevokeAllRefreshTokensForUser(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE refresh_tokens SET revoked_at=NOW(), updated_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL`,
		userID,
	)
	return err
}

func (r *Repository) CreatePasswordReset(ctx context.Context, userID uuid.UUID, tokenHash string, expiresAt time.Time) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO password_resets (user_id, token_hash, expires_at) VALUES ($1, $2, $3)`,
		userID, tokenHash, expiresAt,
	)
	return err
}

func (r *Repository) GetPasswordResetByHash(ctx context.Context, tokenHash string) (*models.PasswordReset, error) {
	var reset models.PasswordReset
	if err := r.db.GetContext(ctx, &reset, `SELECT * FROM password_resets WHERE token_hash=$1 ORDER BY created_at DESC LIMIT 1`, tokenHash); err != nil {
		return nil, err
	}
	return &reset, nil
}

func (r *Repository) MarkPasswordResetUsed(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE password_resets SET used_at=NOW(), updated_at=NOW() WHERE id=$1`, id)
	return err
}

func (r *Repository) UpdateUserPassword(ctx context.Context, userID uuid.UUID, hash string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET password_hash=$2, updated_at=NOW() WHERE id=$1`, userID, hash)
	return err
}

func (r *Repository) UpsertDeviceSession(ctx context.Context, userID uuid.UUID, deviceID, sessionPassword, label string) (*models.DeviceSession, error) {
	query := `
	INSERT INTO device_sessions (user_id, device_id, session_password, label, is_active, last_active_at)
	VALUES ($1, $2, $3, $4, true, NOW())
	ON CONFLICT (user_id, device_id)
	DO UPDATE SET session_password=EXCLUDED.session_password,
	              label=COALESCE(EXCLUDED.label, device_sessions.label),
	              is_active=true,
	              last_active_at=NOW(),
	              updated_at=NOW()
	RETURNING *`
	var ds models.DeviceSession
	if err := r.db.GetContext(ctx, &ds, query, userID, deviceID, sessionPassword, nullableString(label)); err != nil {
		return nil, err
	}
	return &ds, nil
}

func (r *Repository) GetDeviceSessionByUserID(ctx context.Context, userID uuid.UUID) (*models.DeviceSession, error) {
	var ds models.DeviceSession
	if err := r.db.GetContext(ctx, &ds, `SELECT * FROM device_sessions WHERE user_id=$1 ORDER BY updated_at DESC LIMIT 1`, userID); err != nil {
		return nil, err
	}
	return &ds, nil
}

func (r *Repository) GetDeviceSessionByDeviceID(ctx context.Context, deviceID string) (*models.DeviceSession, error) {
	var ds models.DeviceSession
	if err := r.db.GetContext(ctx, &ds, `SELECT * FROM device_sessions WHERE device_id=$1 ORDER BY updated_at DESC LIMIT 1`, deviceID); err != nil {
		return nil, err
	}
	return &ds, nil
}

func (r *Repository) CanResendVerification(ctx context.Context, userID uuid.UUID, minWait time.Duration) (bool, error) {
	var createdAt sql.NullTime
	if err := r.db.GetContext(ctx, &createdAt,
		`SELECT created_at FROM email_verifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1`, userID,
	); err != nil {
		if err == sql.ErrNoRows {
			return true, nil
		}
		return false, err
	}
	if !createdAt.Valid {
		return true, nil
	}
	return time.Since(createdAt.Time) >= minWait, nil
}

func (r *Repository) SetTwoFactorSecret(ctx context.Context, userID uuid.UUID, encryptedSecret string) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE users SET two_factor_secret=$2, updated_at=NOW() WHERE id=$1`,
		userID, encryptedSecret,
	)
	return err
}

func (r *Repository) EnableTwoFactor(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE users SET two_factor_enabled=true, updated_at=NOW() WHERE id=$1`,
		userID,
	)
	return err
}

func (r *Repository) DisableTwoFactor(ctx context.Context, userID uuid.UUID) error {
	tx, err := r.db.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE users SET two_factor_enabled=false, two_factor_secret=NULL, updated_at=NOW() WHERE id=$1`, userID); err != nil {
		_ = tx.Rollback()
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM totp_backup_codes WHERE user_id=$1`, userID); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

func (r *Repository) ReplaceTOTPBackupCodes(ctx context.Context, userID uuid.UUID, codeHashes []string) error {
	tx, err := r.db.BeginTxx(ctx, nil)
	if err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM totp_backup_codes WHERE user_id=$1`, userID); err != nil {
		_ = tx.Rollback()
		return err
	}
	stmt, err := tx.PrepareContext(ctx, `INSERT INTO totp_backup_codes (user_id, code_hash) VALUES ($1, $2)`)
	if err != nil {
		_ = tx.Rollback()
		return err
	}
	defer stmt.Close()
	for _, codeHash := range codeHashes {
		if _, err := stmt.ExecContext(ctx, userID, codeHash); err != nil {
			_ = tx.Rollback()
			return err
		}
	}
	return tx.Commit()
}

func (r *Repository) ListUnusedTOTPBackupCodes(ctx context.Context, userID uuid.UUID) ([]models.TOTpBackupCode, error) {
	codes := []models.TOTpBackupCode{}
	if err := r.db.SelectContext(ctx, &codes, `SELECT * FROM totp_backup_codes WHERE user_id=$1 AND used_at IS NULL ORDER BY created_at DESC`, userID); err != nil {
		return nil, err
	}
	return codes, nil
}

func (r *Repository) MarkTOTPBackupCodeUsed(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE totp_backup_codes SET used_at=NOW() WHERE id=$1`, id)
	return err
}

func (r *Repository) InsertAuditLog(ctx context.Context, logEntry models.AuditLog) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO audit_logs (user_id, action, resource_type, resource_id, ip_address, user_agent, metadata) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
		nullableUUIDModel(logEntry.UserID), logEntry.Action, nullableStringFromModel(logEntry.ResourceType), nullableStringFromModel(logEntry.ResourceID),
		nullableStringFromModel(logEntry.IPAddress), nullableStringFromModel(logEntry.UserAgent), jsonOrEmpty(logEntry.Metadata),
	)
	return err
}

func (r *Repository) ListAuditLogs(ctx context.Context, filters AuditFilters, cursor string, limit int) ([]models.AuditLog, string, bool, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	cursorID, err := parseCursorUUID(cursor)
	if err != nil {
		return nil, "", false, err
	}
	clauses := []string{"1=1"}
	args := []interface{}{}
	idx := 1
	if filters.UserID != nil {
		clauses = append(clauses, fmt.Sprintf("user_id = $%d", idx))
		args = append(args, *filters.UserID)
		idx++
	}
	if strings.TrimSpace(filters.Action) != "" {
		clauses = append(clauses, fmt.Sprintf("action = $%d", idx))
		args = append(args, strings.TrimSpace(filters.Action))
		idx++
	}
	if strings.TrimSpace(filters.ResourceType) != "" {
		clauses = append(clauses, fmt.Sprintf("resource_type = $%d", idx))
		args = append(args, strings.TrimSpace(filters.ResourceType))
		idx++
	}
	if filters.DateFrom != nil {
		clauses = append(clauses, fmt.Sprintf("created_at >= $%d", idx))
		args = append(args, *filters.DateFrom)
		idx++
	}
	if filters.DateTo != nil {
		clauses = append(clauses, fmt.Sprintf("created_at <= $%d", idx))
		args = append(args, *filters.DateTo)
		idx++
	}
	if cursorID != uuid.Nil {
		clauses = append(clauses, fmt.Sprintf("id < $%d", idx))
		args = append(args, cursorID)
		idx++
	}
	query := fmt.Sprintf(`SELECT * FROM audit_logs WHERE %s ORDER BY created_at DESC, id DESC LIMIT $%d`, strings.Join(clauses, " AND "), idx)
	args = append(args, limit+1)
	rows := []models.AuditLog{}
	if err := r.db.SelectContext(ctx, &rows, query, args...); err != nil {
		return nil, "", false, err
	}
	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}
	next := ""
	if hasMore && len(rows) > 0 {
		next = rows[len(rows)-1].ID.String()
	}
	return rows, next, hasMore, nil
}

func (r *Repository) InsertLoginHistory(ctx context.Context, entry models.LoginHistory) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO login_history (user_id, ip_address, country, city, device_fingerprint, os, app_version, status, failure_reason) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		entry.UserID, nullableStringFromModel(entry.IPAddress), nullableString(entry.Country.String), nullableString(entry.City.String),
		nullableStringFromModel(entry.DeviceFingerprint), nullableStringFromModel(entry.OS), nullableStringFromModel(entry.AppVersion),
		entry.Status, nullableStringFromModel(entry.FailureReason.String),
	)
	return err
}

func (r *Repository) ListLoginHistory(ctx context.Context, userID uuid.UUID, limit int, cursor string) ([]models.LoginHistory, string, bool, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	cursorID, err := parseCursorUUID(cursor)
	if err != nil {
		return nil, "", false, err
	}
	query := `SELECT * FROM login_history WHERE user_id=$1 AND created_at >= NOW() - INTERVAL '90 days'`
	args := []interface{}{userID}
	if cursorID != uuid.Nil {
		query += ` AND id < $2`
		args = append(args, cursorID)
	}
	query += ` ORDER BY created_at DESC, id DESC LIMIT $` + fmt.Sprintf("%d", len(args)+1)
	args = append(args, limit+1)
	rows := []models.LoginHistory{}
	if err := r.db.SelectContext(ctx, &rows, query, args...); err != nil {
		return nil, "", false, err
	}
	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}
	next := ""
	if hasMore && len(rows) > 0 {
		next = rows[len(rows)-1].ID.String()
	}
	return rows, next, hasMore, nil
}

func (r *Repository) AnonymizeOldLoginHistory(ctx context.Context, olderThan time.Time) error {
	_, err := r.db.ExecContext(ctx, `UPDATE login_history SET ip_address=NULL, country=NULL, city=NULL, device_fingerprint=NULL, os=NULL, app_version=NULL, failure_reason=NULL WHERE created_at < $1`, olderThan)
	return err
}

func (r *Repository) UpsertTrustedDevice(ctx context.Context, device models.TrustedDevice) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO trusted_devices (user_id, device_fingerprint, device_name, last_used_at, trusted_at, revoked_at)
		 VALUES ($1, $2, $3, $4, COALESCE($5, NOW()), $6)
		 ON CONFLICT (user_id, device_fingerprint) DO UPDATE SET device_name=EXCLUDED.device_name, last_used_at=EXCLUDED.last_used_at, revoked_at=EXCLUDED.revoked_at, updated_at=NOW()`,
		device.UserID, device.DeviceFingerprint, device.DeviceName, device.LastUsedAt, device.TrustedAt, device.RevokedAt,
	)
	return err
}

func (r *Repository) ListTrustedDevices(ctx context.Context, userID uuid.UUID) ([]models.TrustedDevice, error) {
	var devices []models.TrustedDevice
	if err := r.db.SelectContext(ctx, &devices, `SELECT * FROM trusted_devices WHERE user_id=$1 AND revoked_at IS NULL ORDER BY trusted_at DESC`, userID); err != nil {
		return nil, err
	}
	return devices, nil
}

func (r *Repository) RevokeTrustedDevice(ctx context.Context, id, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE trusted_devices SET revoked_at=NOW(), updated_at=NOW() WHERE id=$1 AND user_id=$2`, id, userID)
	return err
}

func (r *Repository) RevokeAllTrustedDevices(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE trusted_devices SET revoked_at=NOW(), updated_at=NOW() WHERE user_id=$1 AND revoked_at IS NULL`, userID)
	return err
}

func nullableUUIDModel(id uuid.NullUUID) interface{} {
	if !id.Valid {
		return nil
	}
	return id.UUID
}

func nullableStringFromModel(value string) interface{} {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	return trimmed
}

func jsonOrEmpty(raw []byte) []byte {
	if len(raw) == 0 {
		return []byte(`{}`)
	}
	return raw
}
