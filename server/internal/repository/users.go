package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

func (r *Repository) CreateUser(ctx context.Context, user *models.User) error {
	query := `
	INSERT INTO users (username, email, phone, password_hash, avatar_url, display_name, device_id, is_verified, is_online, last_seen_at)
	VALUES ($1, $2, $3, $4, $5, $6, $7, $8, false, NULL)
	RETURNING id, created_at, updated_at`
	return r.db.QueryRowxContext(ctx, query,
		strings.TrimSpace(user.Username), strings.ToLower(strings.TrimSpace(user.Email)), user.Phone, user.PasswordHash,
		user.AvatarURL, user.DisplayName, user.DeviceID, user.IsVerified,
	).Scan(&user.ID, &user.CreatedAt, &user.UpdatedAt)
}

func (r *Repository) UpdateUserAvatar(ctx context.Context, userID uuid.UUID, avatarURL string) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET avatar_url=$2, updated_at=NOW() WHERE id=$1`, userID, nullableString(avatarURL))
	return err
}

func (r *Repository) UpdateUserProfile(
	ctx context.Context,
	userID uuid.UUID,
	username,
	displayName,
	phone,
	bio,
	theme,
	language string,
) (*models.User, error) {
	var user models.User
	query := `
	UPDATE users
	SET username = COALESCE(NULLIF($2, ''), username),
	    display_name = COALESCE($3, display_name),
	    phone = COALESCE($4, phone),
	    bio = COALESCE($5, bio),
	    theme = COALESCE(NULLIF($6, ''), theme),
	    language = COALESCE(NULLIF($7, ''), language),
	    updated_at = NOW()
	WHERE id = $1 AND deleted_at IS NULL
	RETURNING *`
	if err := r.db.GetContext(
		ctx,
		&user,
		query,
		userID,
		strings.TrimSpace(username),
		nullableString(displayName),
		nullableString(phone),
		nullableString(bio),
		strings.TrimSpace(theme),
		strings.TrimSpace(language),
	); err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *Repository) UpdateNotificationPreferences(ctx context.Context, userID uuid.UUID, preferences []byte) error {
	_, err := r.db.ExecContext(
		ctx,
		`UPDATE users SET notification_preferences=$2, updated_at=NOW() WHERE id=$1 AND deleted_at IS NULL`,
		userID,
		preferences,
	)
	return err
}

func (r *Repository) GetUserByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	var user models.User
	if err := r.db.GetContext(ctx, &user, `SELECT * FROM users WHERE id=$1 AND deleted_at IS NULL`, id); err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *Repository) GetUserByUsername(ctx context.Context, username string) (*models.User, error) {
	var user models.User
	if err := r.db.GetContext(ctx, &user, `SELECT * FROM users WHERE username=$1 AND deleted_at IS NULL`, strings.TrimSpace(username)); err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *Repository) GetUserByEmail(ctx context.Context, email string) (*models.User, error) {
	var user models.User
	if err := r.db.GetContext(ctx, &user, `SELECT * FROM users WHERE email=$1 AND deleted_at IS NULL`, strings.ToLower(strings.TrimSpace(email))); err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *Repository) GetUserByPhone(ctx context.Context, phone string) (*models.User, error) {
	var user models.User
	if err := r.db.GetContext(ctx, &user, `SELECT * FROM users WHERE phone=$1 AND deleted_at IS NULL`, strings.TrimSpace(phone)); err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *Repository) SearchUsers(ctx context.Context, q string, cursor string, limit int) ([]models.User, string, bool, error) {
	if limit <= 0 || limit > 50 {
		limit = 50
	}
	cursorID, err := parseCursorUUID(cursor)
	if err != nil {
		return nil, "", false, err
	}
	queryText := strings.ToLower(strings.TrimSpace(q))
	if queryText == "" {
		queryText = "%"
	} else {
		queryText = "%" + queryText + "%"
	}
	users := []models.User{}
	query := `
	SELECT * FROM users
	WHERE deleted_at IS NULL
	  AND (LOWER(username) LIKE $1 OR LOWER(email) LIKE $1 OR LOWER(COALESCE(display_name, '')) LIKE $1)
	  AND ($2::uuid IS NULL OR id < $2)
	ORDER BY id DESC
	LIMIT $3`
	var cursorArg interface{}
	if cursorID == uuid.Nil {
		cursorArg = nil
	} else {
		cursorArg = cursorID
	}
	if err := r.db.SelectContext(ctx, &users, query, queryText, cursorArg, limit+1); err != nil {
		return nil, "", false, err
	}
	hasMore := len(users) > limit
	if hasMore {
		users = users[:limit]
	}
	next := ""
	if hasMore && len(users) > 0 {
		next = users[len(users)-1].ID.String()
	}
	return users, next, hasMore, nil
}

func (r *Repository) SetOnlineStatus(ctx context.Context, userID uuid.UUID, online bool) error {
	query := `UPDATE users SET is_online=$2, last_seen_at=$3, updated_at=NOW() WHERE id=$1`
	var lastSeen interface{}
	if online {
		lastSeen = nil
	} else {
		lastSeen = time.Now().UTC()
	}
	_, err := r.db.ExecContext(ctx, query, userID, online, lastSeen)
	return err
}

func (r *Repository) UsernameOrEmailExists(ctx context.Context, username, email string) (bool, error) {
	var exists bool
	err := r.db.GetContext(ctx, &exists,
		`SELECT EXISTS(SELECT 1 FROM users WHERE (username=$1 OR email=$2) AND deleted_at IS NULL)`,
		strings.TrimSpace(username), strings.ToLower(strings.TrimSpace(email)),
	)
	return exists, err
}

func (r *Repository) DeviceIDExists(ctx context.Context, deviceID string) (bool, error) {
	var exists bool
	err := r.db.GetContext(ctx, &exists, `SELECT EXISTS(SELECT 1 FROM users WHERE device_id=$1)`, deviceID)
	return exists, err
}

func (r *Repository) GetUsersByIDs(ctx context.Context, ids []uuid.UUID) ([]models.User, error) {
	if len(ids) == 0 {
		return []models.User{}, nil
	}
	query, args, err := sqlx.In(`SELECT * FROM users WHERE id IN (?)`, ids)
	if err != nil {
		return nil, err
	}
	query = r.db.Rebind(query)
	users := []models.User{}
	if err := r.db.SelectContext(ctx, &users, query, args...); err != nil {
		return nil, err
	}
	return users, nil
}

func (r *Repository) GetUserByIdentifier(ctx context.Context, kind, identifier string) (*models.User, error) {
	switch kind {
	case "email":
		return r.GetUserByEmail(ctx, identifier)
	case "phone":
		return r.GetUserByPhone(ctx, identifier)
	case "username":
		return r.GetUserByUsername(ctx, identifier)
	default:
		return nil, fmt.Errorf("unknown identifier kind")
	}
}

func (r *Repository) GetUserByDeviceID(ctx context.Context, deviceID string) (*models.User, error) {
	var user models.User
	if err := r.db.GetContext(ctx, &user, `SELECT * FROM users WHERE device_id=$1 AND deleted_at IS NULL`, strings.TrimSpace(deviceID)); err != nil {
		return nil, err
	}
	return &user, nil
}

func (r *Repository) GetUserByNormalizedDeviceID(ctx context.Context, deviceID string) (*models.User, error) {
	var user models.User
	if err := r.db.GetContext(ctx, &user,
		`SELECT *
		 FROM users
		 WHERE deleted_at IS NULL
		   AND regexp_replace(lower(device_id), '[^a-z0-9]', '', 'g') = regexp_replace(lower($1), '[^a-z0-9]', '', 'g')
		   AND regexp_replace(lower($1), '[^a-z0-9]', '', 'g') <> ''
		 LIMIT 1`,
		strings.TrimSpace(deviceID),
	); err != nil {
		return nil, err
	}
	return &user, nil
}

func nullableStringToPtr(v sql.NullString) *string {
	if !v.Valid {
		return nil
	}
	value := v.String
	return &value
}
