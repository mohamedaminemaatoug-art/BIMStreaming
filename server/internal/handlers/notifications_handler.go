package handlers

import (
	"context"
	"net/http"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

type createNotificationRequest struct {
	UserID  string                 `json:"user_id"`
	Type    string                 `json:"type"`
	Payload map[string]interface{} `json:"payload"`
}

func (a *App) CreateNotificationForUser(ctx context.Context, userID uuid.UUID, nType string, payload any) (*models.Notification, error) {
	notif, err := a.Repo.CreateNotification(ctx, userID, nType, payload)
	if err != nil {
		return nil, err
	}
	if a.Hub != nil && a.Hub.HasConnections(userID.String()) {
		a.Hub.PublishToUser(userID.String(), "notification:new", notif)
	} else if a.Push != nil {
		a.Push.Enqueue(userID, notif)
	}
	return notif, nil
}

func (a *App) CreateNotification(w http.ResponseWriter, r *http.Request) {
	_, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body createNotificationRequest
	if err := parseJSON(r, &body); err != nil || body.UserID == "" || body.Type == "" {
		badRequest(w, "invalid body")
		return
	}
	userID, err := uuid.Parse(body.UserID)
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	notif, err := a.CreateNotificationForUser(r.Context(), userID, body.Type, body.Payload)
	if err != nil {
		internalError(w, "failed to create notification")
		return
	}
	writeJSON(w, http.StatusCreated, notif)
}

func (a *App) GetNotifications(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	cursor := r.URL.Query().Get("cursor")
	limit := intQueryDefault(r, "limit", 50)
	notifs, next, hasMore, err := a.Repo.ListNotifications(r.Context(), userID, cursor, limit)
	if err != nil {
		internalError(w, "failed to load notifications")
		return
	}
	count, _ := a.Repo.GetUnreadNotificationCount(r.Context(), userID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"data":         notifs,
		"next_cursor":  next,
		"has_more":     hasMore,
		"unread_count": count,
	})
}

func (a *App) MarkAllNotificationsRead(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	if err := a.Repo.MarkAllNotificationsRead(r.Context(), userID); err != nil {
		internalError(w, "failed to mark notifications")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "all notifications marked read"})
}

func (a *App) MarkNotificationRead(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	nID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid notification id")
		return
	}
	if err := a.Repo.MarkNotificationRead(r.Context(), userID, nID); err != nil {
		internalError(w, "failed to mark notification")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "notification marked read"})
}
