package repository

import (
	"context"
	"time"
)

func (r *Repository) CleanupExpiredAuthTokens(ctx context.Context) error {
	if _, err := r.db.ExecContext(ctx, `DELETE FROM refresh_tokens WHERE expires_at < NOW()`); err != nil {
		return err
	}
	return nil
}

func (r *Repository) CleanupExpiredEmailVerificationTokens(ctx context.Context) error {
	if _, err := r.db.ExecContext(ctx, `DELETE FROM email_verifications WHERE expires_at < NOW() OR used_at IS NOT NULL`); err != nil {
		return err
	}
	return nil
}

func (r *Repository) CleanupExpiredPasswordResetTokens(ctx context.Context) error {
	if _, err := r.db.ExecContext(ctx, `DELETE FROM password_resets WHERE expires_at < NOW() OR used_at IS NOT NULL`); err != nil {
		return err
	}
	return nil
}

func (r *Repository) CleanupExpiredRemoteSessionInvites(ctx context.Context) error {
	if _, err := r.db.ExecContext(ctx, `UPDATE remote_session_invites SET status='expired', updated_at=NOW() WHERE status='pending' AND expires_at < NOW()`); err != nil {
		return err
	}
	return nil
}

func (r *Repository) CleanupOldLoginHistory(ctx context.Context, before time.Time) error {
	return r.AnonymizeOldLoginHistory(ctx, before)
}

func (r *Repository) CleanupSoftDeletedMessages(ctx context.Context, before time.Time) error {
	if _, err := r.db.ExecContext(ctx, `UPDATE direct_messages SET content='[deleted]', updated_at=NOW() WHERE is_deleted=true AND updated_at < $1 AND content <> '[deleted]'`, before); err != nil {
		return err
	}
	if _, err := r.db.ExecContext(ctx, `UPDATE community_messages SET content='[deleted]', updated_at=NOW() WHERE is_deleted=true AND updated_at < $1 AND content <> '[deleted]'`, before); err != nil {
		return err
	}
	return nil
}

func (r *Repository) CleanupExpiredStatuses(ctx context.Context) error {
	return r.ClearExpiredStatuses(ctx)
}
