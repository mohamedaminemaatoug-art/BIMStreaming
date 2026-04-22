package handlers

import (
	"net/http"
	"strings"

	"bimstreaming/server/internal/repository"
)

func (a *App) ensureSuperadmin(r *http.Request) bool {
	userID, err := currentUserID(r)
	if err != nil {
		return false
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		return false
	}
	return user.IsSuperadmin
}

func (a *App) AdminListUsers(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	page := intQueryDefault(r, "page", 1)
	limit := intQueryDefault(r, "limit", 50)
	filters := repository.AdminUserFilters{Query: strings.TrimSpace(r.URL.Query().Get("q"))}
	if raw := strings.TrimSpace(strings.ToLower(r.URL.Query().Get("verified"))); raw == "true" || raw == "false" {
		value := raw == "true"
		filters.Verified = &value
	}
	if raw := strings.TrimSpace(strings.ToLower(r.URL.Query().Get("banned"))); raw == "true" || raw == "false" {
		value := raw == "true"
		filters.Banned = &value
	}
	users, total, err := a.Repo.ListUsersAdmin(r.Context(), page, limit, filters)
	if err != nil {
		internalError(w, "failed to load users")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": users, "page": page, "limit": limit, "total": total})
}

func (a *App) AdminGetUser(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	targetID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	user, sub, plan, audits, err := a.Repo.GetAdminUserDetail(r.Context(), targetID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"user": user, "subscription": sub, "plan": plan, "audit": audits})
}

func (a *App) AdminBanUser(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	targetID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	_ = parseJSON(r, &body)
	if err := a.Repo.SetUserBan(r.Context(), targetID, true, body.Reason); err != nil {
		internalError(w, "failed to ban user")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "user banned"})
}

func (a *App) AdminUnbanUser(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	targetID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	if err := a.Repo.SetUserBan(r.Context(), targetID, false, ""); err != nil {
		internalError(w, "failed to unban user")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "user unbanned"})
}

func (a *App) AdminVerifyUser(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	targetID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	if err := a.Repo.SetUserEmailVerified(r.Context(), targetID, true); err != nil {
		internalError(w, "failed to verify user")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "user verified"})
}

func (a *App) AdminListCommunities(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	page := intQueryDefault(r, "page", 1)
	limit := intQueryDefault(r, "limit", 50)
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	rows, total, err := a.Repo.ListCommunitiesAdmin(r.Context(), page, limit, query)
	if err != nil {
		internalError(w, "failed to load communities")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": rows, "page": page, "limit": limit, "total": total})
}

func (a *App) AdminListSessions(w http.ResponseWriter, r *http.Request) {
	a.adminListSessionsInternal(w, r, false)
}

func (a *App) AdminListActiveSessions(w http.ResponseWriter, r *http.Request) {
	a.adminListSessionsInternal(w, r, true)
}

func (a *App) adminListSessionsInternal(w http.ResponseWriter, r *http.Request, activeOnly bool) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	page := intQueryDefault(r, "page", 1)
	limit := intQueryDefault(r, "limit", 50)
	rows, total, err := a.Repo.ListRemoteSessionsAdmin(r.Context(), page, limit, activeOnly)
	if err != nil {
		internalError(w, "failed to load sessions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": rows, "page": page, "limit": limit, "total": total, "active_only": activeOnly})
}

func (a *App) AdminGetStats(w http.ResponseWriter, r *http.Request) {
	if !a.ensureSuperadmin(r) {
		forbidden(w, "superadmin access required")
		return
	}
	stats, err := a.Repo.GetPlatformStats(r.Context())
	if err != nil {
		internalError(w, "failed to load stats")
		return
	}
	writeJSON(w, http.StatusOK, stats)
}
