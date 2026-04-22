package repository

import (
	"context"
	"database/sql"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

func (r *Repository) GetUserStatus(ctx context.Context, userID uuid.UUID) (*models.UserStatus, error) {
	var status models.UserStatus
	if err := r.db.GetContext(ctx, &status, `SELECT * FROM user_status WHERE user_id=$1 LIMIT 1`, userID); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &status, nil
}

func (r *Repository) UpsertUserStatus(ctx context.Context, status models.UserStatus) (*models.UserStatus, error) {
	var saved models.UserStatus
	if err := r.db.GetContext(ctx, &saved, `
		INSERT INTO user_status (user_id, emoji, message, availability, expires_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (user_id)
		DO UPDATE SET emoji=EXCLUDED.emoji, message=EXCLUDED.message, availability=EXCLUDED.availability, expires_at=EXCLUDED.expires_at, updated_at=NOW()
		RETURNING *`, status.UserID, status.Emoji, status.Message, status.Availability, status.ExpiresAt); err != nil {
		return nil, err
	}
	return &saved, nil
}

func (r *Repository) ClearExpiredStatuses(ctx context.Context) error {
	_, err := r.db.ExecContext(ctx, `UPDATE user_status SET availability='offline', message=NULL, emoji=NULL, expires_at=NULL, updated_at=NOW() WHERE expires_at IS NOT NULL AND expires_at < NOW()`)
	return err
}

func (r *Repository) ListStatusesByUserIDs(ctx context.Context, userIDs []uuid.UUID) ([]models.UserStatus, error) {
	if len(userIDs) == 0 {
		return []models.UserStatus{}, nil
	}
	query, args, err := sqlx.In(`SELECT * FROM user_status WHERE user_id IN (?)`, userIDs)
	if err != nil {
		return nil, err
	}
	query = r.db.Rebind(query)
	var statuses []models.UserStatus
	if err := r.db.SelectContext(ctx, &statuses, query, args...); err != nil {
		return nil, err
	}
	return statuses, nil
}

func (r *Repository) TouchUserStatus(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE user_status SET updated_at=NOW() WHERE user_id=$1`, userID)
	return err
}

func (r *Repository) DeleteUserStatus(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM user_status WHERE user_id=$1`, userID)
	return err
}
