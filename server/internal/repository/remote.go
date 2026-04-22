package repository

import (
	"context"
	"database/sql"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) CreateRemoteInvite(ctx context.Context, requesterID uuid.UUID, targetDeviceID string, expiresAt time.Time) (*models.RemoteSessionInvite, error) {
	var inv models.RemoteSessionInvite
	if err := r.db.GetContext(ctx, &inv,
		`INSERT INTO remote_session_invites (requester_id, target_device_id, status, expires_at)
		 VALUES ($1,$2,'pending',$3)
		 RETURNING *`,
		requesterID, targetDeviceID, expiresAt,
	); err != nil {
		return nil, err
	}
	return &inv, nil
}

func (r *Repository) GetRemoteInviteByID(ctx context.Context, inviteID uuid.UUID) (*models.RemoteSessionInvite, error) {
	var inv models.RemoteSessionInvite
	if err := r.db.GetContext(ctx, &inv, `SELECT * FROM remote_session_invites WHERE id=$1`, inviteID); err != nil {
		return nil, err
	}
	return &inv, nil
}

func (r *Repository) UpdateRemoteInviteStatus(ctx context.Context, inviteID uuid.UUID, status, sessionToken string) (*models.RemoteSessionInvite, error) {
	var tokenArg interface{}
	if sessionToken == "" {
		tokenArg = nil
	} else {
		tokenArg = sessionToken
	}
	var inv models.RemoteSessionInvite
	if err := r.db.GetContext(ctx, &inv,
		`UPDATE remote_session_invites
		 SET status=$2, session_token=COALESCE($3, session_token), updated_at=NOW()
		 WHERE id=$1
		 RETURNING *`,
		inviteID, status, tokenArg,
	); err != nil {
		return nil, err
	}
	return &inv, nil
}

func (r *Repository) ExpirePendingRemoteInvites(ctx context.Context) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE remote_session_invites SET status='expired', updated_at=NOW() WHERE status='pending' AND expires_at < NOW()`,
	)
	return err
}

func (r *Repository) CreateActivityLog(ctx context.Context, log models.ActivityLog) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO activity_log (user_id, target_username, target_device_id, session_type, duration_seconds, status, started_at, ended_at)
		 VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
		log.UserID, log.TargetUsername, log.TargetDeviceID, log.SessionType, log.DurationSeconds, log.Status, log.StartedAt, log.EndedAt,
	)
	return err
}

func (r *Repository) ListActivityLog(ctx context.Context, userID uuid.UUID, cursor string, limit int) ([]models.ActivityLog, string, bool, error) {
	if limit <= 0 || limit > 50 {
		limit = 50
	}
	cursorID, err := parseCursorUUID(cursor)
	if err != nil {
		return nil, "", false, err
	}
	var cursorArg interface{}
	if cursorID == uuid.Nil {
		cursorArg = nil
	} else {
		cursorArg = cursorID
	}
	rows := []models.ActivityLog{}
	if err := r.db.SelectContext(ctx, &rows,
		`SELECT * FROM activity_log WHERE user_id=$1 AND ($2::uuid IS NULL OR id < $2) ORDER BY id DESC LIMIT $3`,
		userID, cursorArg, limit+1,
	); err != nil {
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

func (r *Repository) FindUserIDByDeviceID(ctx context.Context, deviceID string) (uuid.UUID, error) {
	var userID uuid.UUID
	if err := r.db.GetContext(ctx, &userID,
		`SELECT user_id FROM device_sessions WHERE device_id=$1 ORDER BY updated_at DESC LIMIT 1`,
		deviceID,
	); err != nil {
		return uuid.Nil, err
	}
	return userID, nil
}

func (r *Repository) NullableDuration(duration int) sql.NullInt32 {
	if duration <= 0 {
		return sql.NullInt32{}
	}
	return sql.NullInt32{Int32: int32(duration), Valid: true}
}
