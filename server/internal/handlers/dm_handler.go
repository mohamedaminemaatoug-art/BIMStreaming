package handlers

import (
	"net/http"
	"time"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (a *App) GetDMHistory(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	otherID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	cursor := r.URL.Query().Get("cursor")
	limit := intQueryDefault(r, "limit", 50)
	messages, next, hasMore, err := a.Repo.GetDirectMessages(r.Context(), userID, otherID, cursor, limit)
	if err != nil {
		internalError(w, "failed to load messages")
		return
	}
	decrypted := make([]map[string]interface{}, 0, len(messages))
	for _, msg := range messages {
		key, err := auth.DeriveDMKey(a.EncryptionKey, msg.SenderID.String(), msg.RecipientID.String())
		if err != nil {
			continue
		}
		plain, err := auth.DecryptAESGCM(msg.Content, key)
		if err != nil {
			continue
		}
		decrypted = append(decrypted, map[string]interface{}{
			"id":           msg.ID,
			"sender_id":    msg.SenderID,
			"recipient_id": msg.RecipientID,
			"content":      string(plain),
			"is_read":      msg.IsRead,
			"read_at":      msg.ReadAt,
			"created_at":   msg.CreatedAt,
		})
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: decrypted, NextCursor: next, HasMore: hasMore})
}

func (a *App) SendDM(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	otherID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	var body struct {
		Content string `json:"content"`
	}
	if err := parseJSON(r, &body); err != nil || body.Content == "" {
		badRequest(w, "content is required")
		return
	}
	key, err := auth.DeriveDMKey(a.EncryptionKey, userID.String(), otherID.String())
	if err != nil {
		internalError(w, "failed to derive key")
		return
	}
	encrypted, err := auth.EncryptAESGCM([]byte(body.Content), key)
	if err != nil {
		internalError(w, "failed to encrypt message")
		return
	}
	msg, err := a.Repo.CreateDirectMessage(r.Context(), userID, otherID, encrypted)
	if err != nil {
		internalError(w, "failed to store message")
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{ID: uuid.New(), UserID: uuid.NullUUID{UUID: userID, Valid: true}, Action: "dm_sent", ResourceType: "direct_message", ResourceID: msg.ID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	a.Hub.PublishToUser(otherID.String(), "dm:new", map[string]interface{}{
		"id":           msg.ID,
		"sender_id":    userID,
		"recipient_id": otherID,
		"content":      body.Content,
		"created_at":   msg.CreatedAt,
	})
	_, _ = a.CreateNotificationForUser(r.Context(), otherID, "dm", map[string]interface{}{"from": userID, "at": time.Now().UTC()})
	writeJSON(w, http.StatusCreated, map[string]interface{}{"id": msg.ID})
}

func (a *App) MarkDMRead(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	otherID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	if err := a.Repo.MarkConversationRead(r.Context(), userID, otherID); err != nil {
		internalError(w, "failed to mark as read")
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{ID: uuid.New(), UserID: uuid.NullUUID{UUID: userID, Valid: true}, Action: "dm_read", ResourceType: "direct_message", ResourceID: otherID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	a.Hub.PublishToUser(otherID.String(), "dm:read", map[string]interface{}{"reader_id": userID, "read_at": time.Now().UTC()})
	writeJSON(w, http.StatusOK, map[string]string{"message": "conversation marked read"})
}

func (a *App) ListConversations(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	data, err := a.Repo.ListConversationSummaries(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to list conversations")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": data})
}
