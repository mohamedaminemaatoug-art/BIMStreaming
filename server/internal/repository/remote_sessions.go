package repository

import (
	"context"
	"database/sql"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) CreateRemoteSession(ctx context.Context, inviteID *uuid.UUID, controllerID, hostID uuid.UUID, hostDeviceID, sessionToken, sessionType, quality string) (*models.RemoteSession, error) {
	var session models.RemoteSession
	var inviteArg interface{}
	if inviteID != nil {
		inviteArg = *inviteID
	}
	if err := r.db.GetContext(ctx, &session, `
		INSERT INTO remote_sessions (invite_id, controller_id, host_id, host_device_id, session_token, session_type, quality)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		RETURNING *`, inviteArg, controllerID, hostID, hostDeviceID, sessionToken, sessionType, quality); err != nil {
		return nil, err
	}
	return &session, nil
}

func (r *Repository) GetRemoteSessionByID(ctx context.Context, sessionID uuid.UUID) (*models.RemoteSession, error) {
	var session models.RemoteSession
	if err := r.db.GetContext(ctx, &session, `SELECT * FROM remote_sessions WHERE id=$1`, sessionID); err != nil {
		return nil, err
	}
	return &session, nil
}

func (r *Repository) UpdateRemoteSessionPermissions(ctx context.Context, sessionID uuid.UUID, permissions models.SessionPermission) (*models.SessionPermission, error) {
	var saved models.SessionPermission
	if err := r.db.GetContext(ctx, &saved, `
		INSERT INTO session_permissions (session_id, allow_keyboard, allow_mouse, allow_clipboard, allow_file_transfer, allow_audio, allow_restart, allow_lock_screen)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		ON CONFLICT (session_id)
		DO UPDATE SET allow_keyboard=EXCLUDED.allow_keyboard, allow_mouse=EXCLUDED.allow_mouse, allow_clipboard=EXCLUDED.allow_clipboard, allow_file_transfer=EXCLUDED.allow_file_transfer, allow_audio=EXCLUDED.allow_audio, allow_restart=EXCLUDED.allow_restart, allow_lock_screen=EXCLUDED.allow_lock_screen, updated_at=NOW()
		RETURNING *`, sessionID, permissions.AllowKeyboard, permissions.AllowMouse, permissions.AllowClipboard, permissions.AllowFileTransfer, permissions.AllowAudio, permissions.AllowRestart, permissions.AllowLockScreen); err != nil {
		return nil, err
	}
	return &saved, nil
}

func (r *Repository) GetRemoteSessionPermissions(ctx context.Context, sessionID uuid.UUID) (*models.SessionPermission, error) {
	var perms models.SessionPermission
	if err := r.db.GetContext(ctx, &perms, `SELECT * FROM session_permissions WHERE session_id=$1`, sessionID); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &perms, nil
}

func (r *Repository) UpdateRemoteSessionQuality(ctx context.Context, sessionID uuid.UUID, quality string) (*models.RemoteSession, error) {
	var session models.RemoteSession
	if err := r.db.GetContext(ctx, &session, `UPDATE remote_sessions SET quality=$2, updated_at=NOW() WHERE id=$1 RETURNING *`, sessionID, quality); err != nil {
		return nil, err
	}
	return &session, nil
}

func (r *Repository) UpdateRemoteSessionStats(ctx context.Context, sessionID uuid.UUID, bytesSent, bytesReceived int64, avgLatencyMs *int, durationSeconds *int32, endedAt *time.Time, endReason *string) (*models.RemoteSession, error) {
	var session models.RemoteSession
	if err := r.db.GetContext(ctx, &session, `
		UPDATE remote_sessions
		SET bytes_sent=$2, bytes_received=$3, avg_latency_ms=COALESCE($4, avg_latency_ms), duration_seconds=COALESCE($5, duration_seconds), ended_at=COALESCE($6, ended_at), end_reason=COALESCE($7, end_reason), updated_at=NOW()
		WHERE id=$1
		RETURNING *`, sessionID, bytesSent, bytesReceived, avgLatencyMs, durationSeconds, endedAt, endReason); err != nil {
		return nil, err
	}
	return &session, nil
}

func (r *Repository) EndRemoteSession(ctx context.Context, sessionID uuid.UUID, reason string) (*models.RemoteSession, error) {
	endedAt := time.Now().UTC()
	var session models.RemoteSession
	if err := r.db.GetContext(ctx, &session, `
		UPDATE remote_sessions
		SET ended_at=$2, end_reason=$3, updated_at=NOW()
		WHERE id=$1
		RETURNING *`, sessionID, endedAt, reason); err != nil {
		return nil, err
	}
	return &session, nil
}

func (r *Repository) CreateUnattendedAccess(ctx context.Context, hostUserID, controllerUserID uuid.UUID, passwordHash string) (*models.UnattendedAccess, error) {
	var access models.UnattendedAccess
	if err := r.db.GetContext(ctx, &access, `
		INSERT INTO unattended_access (host_user_id, controller_user_id, access_password_hash, is_active)
		VALUES ($1,$2,$3,true)
		ON CONFLICT (host_user_id, controller_user_id)
		DO UPDATE SET access_password_hash=EXCLUDED.access_password_hash, is_active=true, updated_at=NOW()
		RETURNING *`, hostUserID, controllerUserID, passwordHash); err != nil {
		return nil, err
	}
	return &access, nil
}

func (r *Repository) ListUnattendedAccess(ctx context.Context, hostUserID uuid.UUID) ([]models.UnattendedAccess, error) {
	rows := []models.UnattendedAccess{}
	if err := r.db.SelectContext(ctx, &rows, `SELECT * FROM unattended_access WHERE host_user_id=$1 AND is_active=true ORDER BY created_at DESC`, hostUserID); err != nil {
		return nil, err
	}
	return rows, nil
}

func (r *Repository) DeleteUnattendedAccess(ctx context.Context, accessID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE unattended_access SET is_active=false, updated_at=NOW() WHERE id=$1`, accessID)
	return err
}
