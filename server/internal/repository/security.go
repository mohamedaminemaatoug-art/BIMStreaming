package repository

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"
)

func (r *Repository) IncrementFailedLoginCount(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	if err := r.db.GetContext(ctx, &count, `UPDATE users SET failed_login_count = failed_login_count + 1, last_failed_login_at = NOW(), updated_at = NOW() WHERE id=$1 RETURNING failed_login_count`, userID); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) ResetFailedLoginCount(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET failed_login_count = 0, last_failed_login_at = NULL, locked_until = NULL, updated_at = NOW() WHERE id=$1`, userID)
	return err
}

func (r *Repository) LockUserUntil(ctx context.Context, userID uuid.UUID, until time.Time) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET locked_until=$2, updated_at=NOW() WHERE id=$1`, userID, until)
	return err
}

func (r *Repository) BanUser(ctx context.Context, userID uuid.UUID, reason string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET is_banned=true, ban_reason=$2, updated_at=NOW() WHERE id=$1`, userID, reason)
	return err
}

func (r *Repository) CountFailedLoginsSince(ctx context.Context, userID uuid.UUID, since time.Time) (int, error) {
	var count int
	if err := r.db.GetContext(ctx, &count, `SELECT COUNT(*) FROM login_history WHERE user_id=$1 AND status='failed' AND created_at >= $2`, userID, since); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) HasSuccessfulLoginInCountry(ctx context.Context, userID uuid.UUID, country string) (bool, error) {
	var exists bool
	if err := r.db.GetContext(ctx, &exists, `SELECT EXISTS(SELECT 1 FROM login_history WHERE user_id=$1 AND status='success' AND country=$2)`, userID, country); err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) SetUserBanned(ctx context.Context, userID uuid.UUID, reason string) error {
	return r.BanUser(ctx, userID, reason)
}

func (r *Repository) UpdateUserLockStatus(ctx context.Context, userID uuid.UUID, lockUntil *time.Time, failedCount int) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET locked_until=$2, failed_login_count=$3, updated_at=NOW() WHERE id=$1`, userID, lockUntil, failedCount)
	return err
}

func (r *Repository) RecentFailedLoginCount(ctx context.Context, userID uuid.UUID, since time.Time) (int, error) {
	return r.CountFailedLoginsSince(ctx, userID, since)
}

func (r *Repository) EnsureUserNotLocked(ctx context.Context, userID uuid.UUID) error {
	var lockedUntil time.Time
	if err := r.db.GetContext(ctx, &lockedUntil, `SELECT locked_until FROM users WHERE id=$1`, userID); err != nil {
		return err
	}
	if !lockedUntil.IsZero() && lockedUntil.After(time.Now().UTC()) {
		return fmt.Errorf("account locked")
	}
	return nil
}
