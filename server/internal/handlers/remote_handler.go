package handlers

import (
	"bimstreaming/server/internal/models"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

func (a *App) CreateRemoteInvite(w http.ResponseWriter, r *http.Request) {
	requesterID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	targetIdentifier := strings.TrimSpace(r.PathValue("user_id"))
	if targetIdentifier == "" {
		badRequest(w, "target id is required")
		return
	}

	var targetUserID uuid.UUID
	var targetUser *models.User

	if parsedID, parseErr := parseUUIDParam(r, "user_id"); parseErr == nil {
		if userByID, userErr := a.Repo.GetUserByID(r.Context(), parsedID); userErr == nil {
			targetUserID = parsedID
			targetUser = userByID
		}
	}

	if targetUser == nil {
		userByDeviceID, deviceErr := a.Repo.GetUserByDeviceID(r.Context(), targetIdentifier)
		if deviceErr == nil {
			targetUserID = userByDeviceID.ID
			targetUser = userByDeviceID
		}
	}

	if targetUser == nil {
		userByNormalizedDeviceID, normalizedErr := a.Repo.GetUserByNormalizedDeviceID(r.Context(), targetIdentifier)
		if normalizedErr == nil {
			targetUserID = userByNormalizedDeviceID.ID
			targetUser = userByNormalizedDeviceID
		}
	}

	if targetUser == nil {
		notFound(w, "target user/device not found")
		return
	}
	if requesterID == targetUserID {
		badRequest(w, "cannot invite yourself")
		return
	}
	isFriend, err := a.Repo.AreFriends(r.Context(), requesterID, targetUserID)
	if err != nil {
		internalError(w, "failed to verify friendship")
		return
	}
	var body struct {
		SessionPassword string `json:"session_password"`
	}
	_ = parseJSON(r, &body)
	providedPassword := strings.TrimSpace(body.SessionPassword)
	if providedPassword != "" {
		targetSession, err := a.Repo.GetDeviceSessionByDeviceID(r.Context(), targetUser.DeviceID)
		if err != nil {
			notFound(w, "target session not found")
			return
		}
		if strings.TrimSpace(targetSession.SessionPassword) != providedPassword {
			forbidden(w, "invalid session password")
			return
		}
	} else if !isFriend {
		forbidden(w, "friend invite required")
		return
	}
	invite, err := a.Repo.CreateRemoteInvite(r.Context(), requesterID, targetUser.DeviceID, time.Now().UTC().Add(2*time.Minute))
	if err != nil {
		internalError(w, "failed to create invite")
		return
	}
	a.Hub.PublishToUser(targetUserID.String(), "remote:invite", map[string]interface{}{
		"invite_id":        invite.ID,
		"requester_id":     requesterID,
		"target_device_id": targetUser.DeviceID,
		"expires_at":       invite.ExpiresAt,
	})
	_, _ = a.CreateNotificationForUser(r.Context(), targetUserID, "remote_session_request", map[string]interface{}{"requester_id": requesterID, "invite_id": invite.ID})
	writeJSON(w, http.StatusCreated, invite)
}

func (a *App) ResolveRemoteInvite(w http.ResponseWriter, r *http.Request) {
	responderID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	inviteID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid invite id")
		return
	}
	var body struct {
		Action string `json:"action"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	invite, err := a.Repo.GetRemoteInviteByID(r.Context(), inviteID)
	if err != nil {
		notFound(w, "invite not found")
		return
	}
	targetUserID, err := a.Repo.FindUserIDByDeviceID(r.Context(), invite.TargetDeviceID)
	if err != nil || targetUserID != responderID {
		forbidden(w, "not allowed")
		return
	}
	if time.Now().UTC().After(invite.ExpiresAt) {
		_, _ = a.Repo.UpdateRemoteInviteStatus(r.Context(), inviteID, "expired", "")
		badRequest(w, "invite expired")
		return
	}
	if body.Action == "reject" {
		updated, err := a.Repo.UpdateRemoteInviteStatus(r.Context(), inviteID, "rejected", "")
		if err != nil {
			internalError(w, "failed to reject invite")
			return
		}
		a.Hub.PublishToUser(invite.RequesterID.String(), "remote:invite_rejected", map[string]interface{}{"invite_id": invite.ID})
		writeJSON(w, http.StatusOK, updated)
		return
	}
	if body.Action != "accept" {
		badRequest(w, "action must be accept or reject")
		return
	}
	sessionToken, err := generateSessionPassword(24)
	if err != nil {
		internalError(w, "failed to create session token")
		return
	}
	updated, err := a.Repo.UpdateRemoteInviteStatus(r.Context(), inviteID, "accepted", sessionToken)
	if err != nil {
		internalError(w, "failed to accept invite")
		return
	}
	_, _ = a.Repo.CreateRemoteSession(r.Context(), &invite.ID, invite.RequesterID, responderID, invite.TargetDeviceID, sessionToken, "control", "auto")
	a.Hub.PublishToUser(invite.RequesterID.String(), "remote:invite_accepted", map[string]interface{}{
		"invite_id":        invite.ID,
		"session_token":    sessionToken,
		"target_device_id": invite.TargetDeviceID,
		"target_user_id":   responderID,
	})
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"invite":         updated,
		"session_token":  sessionToken,
		"target_user_id": responderID,
	})
}

func (a *App) GetRemoteHistory(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	cursor := r.URL.Query().Get("cursor")
	limit := intQueryDefault(r, "limit", 50)
	rows, next, hasMore, err := a.Repo.ListActivityLog(r.Context(), userID, cursor, limit)
	if err != nil {
		internalError(w, "failed to load history")
		return
	}
	formatted := make([]map[string]interface{}, 0, len(rows))
	for _, row := range rows {
		duration := int32(0)
		if row.DurationSeconds.Valid {
			duration = row.DurationSeconds.Int32
		}
		formatted = append(formatted, map[string]interface{}{
			"id":               row.ID,
			"target_username":  row.TargetUsername,
			"target_device_id": row.TargetDeviceID,
			"session_type":     row.SessionType,
			"duration_hms":     formatDuration(duration),
			"status":           row.Status,
			"started_at":       row.StartedAt,
			"ended_at":         row.EndedAt,
		})
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: formatted, NextCursor: next, HasMore: hasMore})
}

func formatDuration(seconds int32) string {
	d := time.Duration(seconds) * time.Second
	h := int(d.Hours())
	m := int(d.Minutes()) % 60
	s := int(d.Seconds()) % 60
	return fmt.Sprintf("%02d:%02d:%02d", h, m, s)
}
