package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) CreateDirectMessage(ctx context.Context, senderID, recipientID uuid.UUID, encryptedContent string) (*models.DirectMessage, error) {
	var dm models.DirectMessage
	query := `
	INSERT INTO direct_messages (sender_id, recipient_id, content)
	VALUES ($1, $2, $3)
	RETURNING *`
	if err := r.db.GetContext(ctx, &dm, query, senderID, recipientID, encryptedContent); err != nil {
		return nil, err
	}
	return &dm, nil
}

func (r *Repository) GetDirectMessages(ctx context.Context, userID, otherID uuid.UUID, cursor string, limit int) ([]models.DirectMessage, string, bool, error) {
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
	data := []models.DirectMessage{}
	query := `
	SELECT * FROM direct_messages
	WHERE ((sender_id=$1 AND recipient_id=$2) OR (sender_id=$2 AND recipient_id=$1))
	  AND ($3::uuid IS NULL OR id < $3)
	ORDER BY id DESC
	LIMIT $4`
	if err := r.db.SelectContext(ctx, &data, query, userID, otherID, cursorArg, limit+1); err != nil {
		return nil, "", false, err
	}
	hasMore := len(data) > limit
	if hasMore {
		data = data[:limit]
	}
	next := ""
	if hasMore && len(data) > 0 {
		next = data[len(data)-1].ID.String()
	}
	return data, next, hasMore, nil
}

func (r *Repository) MarkConversationRead(ctx context.Context, userID, otherID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE direct_messages
		 SET is_read=true, read_at=NOW(), updated_at=NOW()
		 WHERE sender_id=$2 AND recipient_id=$1 AND is_read=false`,
		userID, otherID,
	)
	return err
}

func (r *Repository) ListConversationSummaries(ctx context.Context, userID uuid.UUID) ([]map[string]interface{}, error) {
	rows, err := r.db.QueryxContext(ctx, `
	SELECT
	  CASE WHEN sender_id=$1 THEN recipient_id ELSE sender_id END AS contact_id,
	  MAX(created_at) AS last_message_at,
	  SUM(CASE WHEN recipient_id=$1 AND is_read=false THEN 1 ELSE 0 END) AS unread_count
	FROM direct_messages
	WHERE sender_id=$1 OR recipient_id=$1
	GROUP BY contact_id
	ORDER BY last_message_at DESC`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var summaries []map[string]interface{}
	for rows.Next() {
		entry := map[string]interface{}{}
		if err := rows.MapScan(entry); err != nil {
			return nil, err
		}
		summaries = append(summaries, entry)
	}
	return summaries, nil
}

func (r *Repository) CreateCommunityMessage(ctx context.Context, communityID, senderID uuid.UUID, content string) (*models.CommunityMessage, error) {
	var msg models.CommunityMessage
	if err := r.db.GetContext(ctx, &msg,
		`INSERT INTO community_messages (community_id, sender_id, content) VALUES ($1,$2,$3) RETURNING *`,
		communityID, senderID, content,
	); err != nil {
		return nil, err
	}
	return &msg, nil
}

func (r *Repository) GetCommunityMessageByID(ctx context.Context, messageID uuid.UUID) (*models.CommunityMessage, error) {
	var msg models.CommunityMessage
	if err := r.db.GetContext(ctx, &msg, `SELECT * FROM community_messages WHERE id=$1`, messageID); err != nil {
		return nil, err
	}
	return &msg, nil
}

func (r *Repository) UpdateCommunityMessage(ctx context.Context, messageID uuid.UUID, content string) (*models.CommunityMessage, error) {
	var msg models.CommunityMessage
	if err := r.db.GetContext(ctx, &msg, `
		UPDATE community_messages
		SET content=$2, is_edited=true, edited_at=NOW(), updated_at=NOW()
		WHERE id=$1 AND is_deleted=false
		RETURNING *`, messageID, strings.TrimSpace(content)); err != nil {
		return nil, err
	}
	return &msg, nil
}

func (r *Repository) DeleteCommunityMessage(ctx context.Context, messageID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE community_messages SET is_deleted=true, updated_at=NOW() WHERE id=$1`, messageID)
	return err
}

func (r *Repository) AddMessageReaction(ctx context.Context, messageID uuid.UUID, messageType string, userID uuid.UUID, emoji string) error {
	_, err := r.db.ExecContext(ctx, `INSERT INTO message_reactions (message_id, message_type, user_id, emoji) VALUES ($1,$2,$3,$4) ON CONFLICT (message_id, message_type, user_id, emoji) DO NOTHING`, messageID, messageType, userID, strings.TrimSpace(emoji))
	return err
}

func (r *Repository) RemoveMessageReaction(ctx context.Context, messageID uuid.UUID, messageType string, userID uuid.UUID, emoji string) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM message_reactions WHERE message_id=$1 AND message_type=$2 AND user_id=$3 AND emoji=$4`, messageID, messageType, userID, strings.TrimSpace(emoji))
	return err
}

func (r *Repository) ListMessageReactions(ctx context.Context, messageID uuid.UUID, messageType string) ([]models.MessageReaction, error) {
	reactions := []models.MessageReaction{}
	if err := r.db.SelectContext(ctx, &reactions, `SELECT * FROM message_reactions WHERE message_id=$1 AND message_type=$2 ORDER BY created_at ASC`, messageID, messageType); err != nil {
		return nil, err
	}
	return reactions, nil
}

func (r *Repository) AddMessageAttachment(ctx context.Context, messageID uuid.UUID, messageType string, uploaderID uuid.UUID, fileName string, fileSize int64, mimeType, storageURL, thumbnailURL string) (*models.MessageAttachment, error) {
	var att models.MessageAttachment
	if err := r.db.GetContext(ctx, &att, `
		INSERT INTO message_attachments (message_id, message_type, uploader_id, file_name, file_size_bytes, mime_type, storage_url, thumbnail_url)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
		RETURNING *`, messageID, messageType, uploaderID, fileName, nullableInt64(fileSize), nullableString(mimeType), storageURL, nullableString(thumbnailURL)); err != nil {
		return nil, err
	}
	return &att, nil
}

func (r *Repository) ListMessageAttachments(ctx context.Context, messageID uuid.UUID, messageType string) ([]models.MessageAttachment, error) {
	attachments := []models.MessageAttachment{}
	if err := r.db.SelectContext(ctx, &attachments, `SELECT * FROM message_attachments WHERE message_id=$1 AND message_type=$2 ORDER BY created_at ASC`, messageID, messageType); err != nil {
		return nil, err
	}
	return attachments, nil
}

func (r *Repository) DeleteMessageAttachment(ctx context.Context, attachmentID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM message_attachments WHERE id=$1`, attachmentID)
	return err
}

func (r *Repository) ListCommunityMessages(ctx context.Context, communityID uuid.UUID, cursor string, limit int) ([]models.CommunityMessage, string, bool, error) {
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
	data := []models.CommunityMessage{}
	if err := r.db.SelectContext(ctx, &data,
		`SELECT * FROM community_messages WHERE community_id=$1 AND ($2::uuid IS NULL OR id < $2) ORDER BY id DESC LIMIT $3`,
		communityID, cursorArg, limit+1,
	); err != nil {
		return nil, "", false, err
	}
	hasMore := len(data) > limit
	if hasMore {
		data = data[:limit]
	}
	next := ""
	if hasMore && len(data) > 0 {
		next = data[len(data)-1].ID.String()
	}
	return data, next, hasMore, nil
}

func (r *Repository) CreateNotification(ctx context.Context, userID uuid.UUID, nType string, payload any) (*models.Notification, error) {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	var notif models.Notification
	if err := r.db.GetContext(ctx, &notif,
		`INSERT INTO notifications (user_id, type, payload) VALUES ($1,$2,$3) RETURNING *`,
		userID, nType, encoded,
	); err != nil {
		return nil, err
	}
	return &notif, nil
}

func (r *Repository) ListNotifications(ctx context.Context, userID uuid.UUID, cursor string, limit int) ([]models.Notification, string, bool, error) {
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
	rows := []models.Notification{}
	if err := r.db.SelectContext(ctx, &rows,
		`SELECT * FROM notifications WHERE user_id=$1 AND ($2::uuid IS NULL OR id < $2) ORDER BY id DESC LIMIT $3`,
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

func (r *Repository) MarkAllNotificationsRead(ctx context.Context, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE notifications SET is_read=true, updated_at=NOW() WHERE user_id=$1 AND is_read=false`, userID)
	return err
}

func (r *Repository) MarkNotificationRead(ctx context.Context, userID, notificationID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE notifications SET is_read=true, updated_at=NOW() WHERE user_id=$1 AND id=$2`, userID, notificationID)
	return err
}

func (r *Repository) GetUnreadNotificationCount(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	if err := r.db.GetContext(ctx, &count, `SELECT COUNT(*) FROM notifications WHERE user_id=$1 AND is_read=false`, userID); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) GetMutualFriendCount(ctx context.Context, userID, targetID uuid.UUID) (int, error) {
	query := `
	WITH f1 AS (
	  SELECT CASE WHEN requester_id=$1 THEN addressee_id ELSE requester_id END AS friend_id
	  FROM friendships
	  WHERE status='accepted' AND deleted_at IS NULL AND (requester_id=$1 OR addressee_id=$1)
	), f2 AS (
	  SELECT CASE WHEN requester_id=$2 THEN addressee_id ELSE requester_id END AS friend_id
	  FROM friendships
	  WHERE status='accepted' AND deleted_at IS NULL AND (requester_id=$2 OR addressee_id=$2)
	)
	SELECT COUNT(*) FROM f1 INNER JOIN f2 ON f1.friend_id=f2.friend_id`
	var count int
	if err := r.db.GetContext(ctx, &count, query, userID, targetID); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) NullTime(t sql.NullTime) interface{} {
	if !t.Valid {
		return nil
	}
	return t.Time
}

func nullableInt64(v int64) interface{} {
	if v <= 0 {
		return nil
	}
	return v
}
