package handlers

import (
	"net/http"
	"strings"
	"time"

	"bimstreaming/server/internal/models"
	"bimstreaming/server/internal/repository"

	"github.com/google/uuid"
)

func (a *App) GetLoginHistory(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	limit := intQueryDefault(r, "limit", 25)
	cursor := strings.TrimSpace(r.URL.Query().Get("cursor"))
	entries, nextCursor, hasMore, err := a.Repo.ListLoginHistory(r.Context(), userID, limit, cursor)
	if err != nil {
		internalError(w, "failed to load login history")
		return
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: entries, NextCursor: nextCursor, HasMore: hasMore})
}

func (a *App) GetTrustedDevices(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	devices, err := a.Repo.ListTrustedDevices(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to load trusted devices")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": devices})
}

func (a *App) RevokeTrustedDevice(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	deviceID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid device id")
		return
	}
	if err := a.Repo.RevokeTrustedDevice(r.Context(), deviceID, userID); err != nil {
		internalError(w, "failed to revoke device")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "trusted device revoked"})
}

func (a *App) RevokeAllSessions(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	if err := a.Repo.RevokeAllRefreshTokensForUser(r.Context(), userID); err != nil {
		internalError(w, "failed to revoke sessions")
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{Action: "revoke_all_sessions", ResourceType: "security", ResourceID: userID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	writeJSON(w, http.StatusOK, map[string]string{"message": "sessions revoked"})
}

func (a *App) GetAuditLogs(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil || !user.IsSuperadmin {
		forbidden(w, "superadmin access required")
		return
	}
	filters := repository.AuditFilters{
		Action:       strings.TrimSpace(r.URL.Query().Get("action")),
		ResourceType: strings.TrimSpace(r.URL.Query().Get("resource_type")),
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("user_id")); raw != "" {
		if parsed, parseErr := uuid.Parse(raw); parseErr == nil {
			filters.UserID = &parsed
		}
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("from")); raw != "" {
		if parsed, parseErr := time.Parse(time.RFC3339, raw); parseErr == nil {
			filters.DateFrom = &parsed
		}
	}
	if raw := strings.TrimSpace(r.URL.Query().Get("to")); raw != "" {
		if parsed, parseErr := time.Parse(time.RFC3339, raw); parseErr == nil {
			filters.DateTo = &parsed
		}
	}
	limit := intQueryDefault(r, "limit", 50)
	cursor := strings.TrimSpace(r.URL.Query().Get("cursor"))
	entries, nextCursor, hasMore, err := a.Repo.ListAuditLogs(r.Context(), filters, cursor, limit)
	if err != nil {
		internalError(w, "failed to load audit logs")
		return
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: entries, NextCursor: nextCursor, HasMore: hasMore})
}
