package repository

import (
	"context"
	"strings"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) RegisterPushToken(ctx context.Context, userID uuid.UUID, token, platform, deviceFingerprint string) (*models.PushToken, error) {
	var saved models.PushToken
	if err := r.db.GetContext(ctx, &saved, `
		INSERT INTO push_tokens (user_id, token, platform, device_fingerprint, is_active)
		VALUES ($1,$2,$3,$4,true)
		ON CONFLICT (user_id, token)
		DO UPDATE SET platform=EXCLUDED.platform, device_fingerprint=EXCLUDED.device_fingerprint, is_active=true, updated_at=NOW()
		RETURNING *`, userID, strings.TrimSpace(token), strings.TrimSpace(strings.ToLower(platform)), nullableString(deviceFingerprint)); err != nil {
		return nil, err
	}
	return &saved, nil
}

func (r *Repository) UnregisterPushToken(ctx context.Context, userID uuid.UUID, token, deviceFingerprint string) error {
	if strings.TrimSpace(token) != "" {
		_, err := r.db.ExecContext(ctx, `UPDATE push_tokens SET is_active=false, updated_at=NOW() WHERE user_id=$1 AND token=$2`, userID, strings.TrimSpace(token))
		return err
	}
	_, err := r.db.ExecContext(ctx, `UPDATE push_tokens SET is_active=false, updated_at=NOW() WHERE user_id=$1 AND device_fingerprint=$2`, userID, strings.TrimSpace(deviceFingerprint))
	return err
}

func (r *Repository) ListActivePushTokens(ctx context.Context, userID uuid.UUID) ([]models.PushToken, error) {
	rows := []models.PushToken{}
	if err := r.db.SelectContext(ctx, &rows, `SELECT * FROM push_tokens WHERE user_id=$1 AND is_active=true ORDER BY updated_at DESC`, userID); err != nil {
		return nil, err
	}
	return rows, nil
}
