package handlers

import (
	"net/http"
	"strings"
	"time"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (a *App) CreateRemoteSession(w http.ResponseWriter, r *http.Request) {
	controllerID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		HostUserID   string `json:"host_user_id"`
		HostDeviceID string `json:"host_device_id"`
		InviteID     string `json:"invite_id"`
		SessionType  string `json:"session_type"`
		Quality      string `json:"quality"`
		SessionToken string `json:"session_token"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	hostUserID, err := uuid.Parse(body.HostUserID)
	if err != nil {
		badRequest(w, "invalid host user id")
		return
	}
	sessionType := strings.TrimSpace(body.SessionType)
	if sessionType == "" {
		sessionType = "control"
	}
	quality := strings.TrimSpace(body.Quality)
	if quality == "" {
		quality = "auto"
	}
	var inviteID *uuid.UUID
	if strings.TrimSpace(body.InviteID) != "" {
		parsed, err := uuid.Parse(body.InviteID)
		if err != nil {
			badRequest(w, "invalid invite id")
			return
		}
		inviteID = &parsed
	}
	session, err := a.Repo.CreateRemoteSession(r.Context(), inviteID, controllerID, hostUserID, strings.TrimSpace(body.HostDeviceID), strings.TrimSpace(body.SessionToken), sessionType, quality)
	if err != nil {
		internalError(w, "failed to create session")
		return
	}
	_, _ = a.Repo.UpdateRemoteSessionPermissions(r.Context(), session.ID, models.SessionPermission{
		SessionID:         session.ID,
		AllowKeyboard:     true,
		AllowMouse:        true,
		AllowClipboard:    true,
		AllowFileTransfer: false,
		AllowAudio:        false,
		AllowRestart:      false,
		AllowLockScreen:   false,
	})
	writeJSON(w, http.StatusCreated, session)
}

func (a *App) GetRemoteSession(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	sessionID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid session id")
		return
	}
	session, err := a.Repo.GetRemoteSessionByID(r.Context(), sessionID)
	if err != nil {
		notFound(w, "session not found")
		return
	}
	if session.ControllerID != userID && session.HostID != userID {
		forbidden(w, "not allowed")
		return
	}
	perms, _ := a.Repo.GetRemoteSessionPermissions(r.Context(), sessionID)
	writeJSON(w, http.StatusOK, map[string]interface{}{"session": session, "permissions": perms})
}

func (a *App) UpdateRemoteSessionPermissions(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	sessionID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid session id")
		return
	}
	session, err := a.Repo.GetRemoteSessionByID(r.Context(), sessionID)
	if err != nil {
		notFound(w, "session not found")
		return
	}
	if session.ControllerID != userID && session.HostID != userID {
		forbidden(w, "not allowed")
		return
	}
	var body models.SessionPermission
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	body.SessionID = sessionID
	saved, err := a.Repo.UpdateRemoteSessionPermissions(r.Context(), sessionID, body)
	if err != nil {
		internalError(w, "failed to update permissions")
		return
	}
	writeJSON(w, http.StatusOK, saved)
}

func (a *App) UpdateRemoteSessionQuality(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	sessionID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid session id")
		return
	}
	session, err := a.Repo.GetRemoteSessionByID(r.Context(), sessionID)
	if err != nil {
		notFound(w, "session not found")
		return
	}
	if session.ControllerID != userID && session.HostID != userID {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Quality string `json:"quality"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Quality) == "" {
		badRequest(w, "quality is required")
		return
	}
	saved, err := a.Repo.UpdateRemoteSessionQuality(r.Context(), sessionID, strings.TrimSpace(body.Quality))
	if err != nil {
		internalError(w, "failed to update quality")
		return
	}
	writeJSON(w, http.StatusOK, saved)
}

func (a *App) UpdateRemoteSessionStats(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	sessionID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid session id")
		return
	}
	session, err := a.Repo.GetRemoteSessionByID(r.Context(), sessionID)
	if err != nil {
		notFound(w, "session not found")
		return
	}
	if session.ControllerID != userID && session.HostID != userID {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		BytesSent     int64  `json:"bytes_sent"`
		BytesReceived int64  `json:"bytes_received"`
		AvgLatencyMs  *int   `json:"avg_latency_ms"`
		DurationSec   *int32 `json:"duration_seconds"`
		EndReason     string `json:"end_reason"`
		EndedAt       string `json:"ended_at"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	var endedAt *time.Time
	if strings.TrimSpace(body.EndedAt) != "" {
		parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(body.EndedAt))
		if err != nil {
			badRequest(w, "invalid ended_at")
			return
		}
		endedAt = &parsed
	}
	var reason *string
	if strings.TrimSpace(body.EndReason) != "" {
		value := strings.TrimSpace(body.EndReason)
		reason = &value
	}
	saved, err := a.Repo.UpdateRemoteSessionStats(r.Context(), sessionID, body.BytesSent, body.BytesReceived, body.AvgLatencyMs, body.DurationSec, endedAt, reason)
	if err != nil {
		internalError(w, "failed to update stats")
		return
	}
	writeJSON(w, http.StatusOK, saved)
}

func (a *App) EndRemoteSession(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	sessionID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid session id")
		return
	}
	session, err := a.Repo.GetRemoteSessionByID(r.Context(), sessionID)
	if err != nil {
		notFound(w, "session not found")
		return
	}
	if session.ControllerID != userID && session.HostID != userID {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	_ = parseJSON(r, &body)
	saved, err := a.Repo.EndRemoteSession(r.Context(), sessionID, strings.TrimSpace(body.Reason))
	if err != nil {
		internalError(w, "failed to end session")
		return
	}

	peerID := session.HostID
	if userID == session.HostID {
		peerID = session.ControllerID
	}
	peerUsername := ""
	if peer, pErr := a.Repo.GetUserByID(r.Context(), peerID); pErr == nil {
		peerUsername = peer.Username
	}
	startedAt := time.Now()
	if saved.StartedAt.Valid {
		startedAt = saved.StartedAt.Time
	}
	_ = a.Repo.CreateActivityLog(r.Context(), models.ActivityLog{
		UserID:          userID,
		TargetUsername:  peerUsername,
		TargetDeviceID:  session.HostDeviceID,
		SessionType:     session.SessionType,
		DurationSeconds: saved.DurationSeconds,
		Status:          "ended",
		StartedAt:       startedAt,
		EndedAt:         saved.EndedAt,
	})

	writeJSON(w, http.StatusOK, saved)
}

func (a *App) CreateUnattendedAccess(w http.ResponseWriter, r *http.Request) {
	hostUserID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		ControllerUserID string `json:"controller_user_id"`
		Password         string `json:"password"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.ControllerUserID) == "" || strings.TrimSpace(body.Password) == "" {
		badRequest(w, "controller_user_id and password are required")
		return
	}
	controllerID, err := uuid.Parse(body.ControllerUserID)
	if err != nil {
		badRequest(w, "invalid controller user id")
		return
	}
	passwordHash, err := auth.HashPassword(body.Password)
	if err != nil {
		internalError(w, "failed to hash password")
		return
	}
	access, err := a.Repo.CreateUnattendedAccess(r.Context(), hostUserID, controllerID, passwordHash)
	if err != nil {
		internalError(w, "failed to create unattended access")
		return
	}
	writeJSON(w, http.StatusCreated, access)
}

func (a *App) ListUnattendedAccess(w http.ResponseWriter, r *http.Request) {
	hostUserID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	rows, err := a.Repo.ListUnattendedAccess(r.Context(), hostUserID)
	if err != nil {
		internalError(w, "failed to load unattended access")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": rows})
}

func (a *App) DeleteUnattendedAccess(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	accessID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid access id")
		return
	}
	_ = userID
	if err := a.Repo.DeleteUnattendedAccess(r.Context(), accessID); err != nil {
		internalError(w, "failed to delete unattended access")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "unattended access disabled"})
}
