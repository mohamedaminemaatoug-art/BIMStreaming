package repository

import (
	"context"
	"database/sql"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) QueueDataExport(ctx context.Context, userID uuid.UUID) (*models.DataExportRequest, error) {
	var req models.DataExportRequest
	if err := r.db.GetContext(ctx, &req, `
		INSERT INTO data_export_requests (user_id, status)
		VALUES ($1, 'pending')
		RETURNING *`, userID); err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *Repository) MarkDataExportReady(ctx context.Context, exportID uuid.UUID, downloadURL string) (*models.DataExportRequest, error) {
	var req models.DataExportRequest
	if err := r.db.GetContext(ctx, &req, `
		UPDATE data_export_requests
		SET status='ready', download_url=$2, ready_at=NOW(), updated_at=NOW()
		WHERE id=$1
		RETURNING *`, exportID, nullableString(downloadURL)); err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *Repository) RequestAccountDeletion(ctx context.Context, userID uuid.UUID, scheduledFor time.Time, reason string) (*models.AccountDeletionRequest, error) {
	var req models.AccountDeletionRequest
	if err := r.db.GetContext(ctx, &req, `
		INSERT INTO account_deletion_requests (user_id, requested_by, reason, status, scheduled_for)
		VALUES ($1, $1, $2, 'scheduled', $3)
		ON CONFLICT (user_id) WHERE status IN ('scheduled', 'pending')
		DO UPDATE SET reason=EXCLUDED.reason, scheduled_for=EXCLUDED.scheduled_for, updated_at=NOW()
		RETURNING *`, userID, nullableString(reason), scheduledFor); err != nil {
		return nil, err
	}
	return &req, nil
}

func (r *Repository) DeleteExpiredDataExports(ctx context.Context, before time.Time) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM data_export_requests WHERE ready_at IS NOT NULL AND ready_at < $1`, before)
	return err
}

func (r *Repository) GetLatestDataExport(ctx context.Context, userID uuid.UUID) (*models.DataExportRequest, error) {
	var req models.DataExportRequest
	if err := r.db.GetContext(ctx, &req, `SELECT * FROM data_export_requests WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1`, userID); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &req, nil
}
