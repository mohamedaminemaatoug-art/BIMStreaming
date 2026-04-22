package handlers

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"strings"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/middleware"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
)

type paginatedResponse struct {
	Data       interface{} `json:"data"`
	NextCursor string      `json:"next_cursor"`
	HasMore    bool        `json:"has_more"`
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func parseJSON(r *http.Request, dst interface{}) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	return decoder.Decode(dst)
}

func badRequest(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusBadRequest, map[string]string{"error": message})
}

func unauthorized(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusUnauthorized, map[string]string{"error": message})
}

func forbidden(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusForbidden, map[string]string{"error": message})
}

func notFound(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusNotFound, map[string]string{"error": message})
}

func internalError(w http.ResponseWriter, message string) {
	writeJSON(w, http.StatusInternalServerError, map[string]string{"error": message})
}

func currentClaims(r *http.Request) (*auth.AccessClaims, bool) {
	return middleware.ClaimsFromContext(r.Context())
}

func currentUserID(r *http.Request) (uuid.UUID, error) {
	claims, ok := currentClaims(r)
	if !ok {
		return uuid.Nil, fmt.Errorf("missing auth claims")
	}
	return uuid.Parse(claims.RegisteredClaims.Subject)
}

func clientIP(r *http.Request) string {
	forwarded := strings.TrimSpace(r.Header.Get("X-Forwarded-For"))
	if forwarded != "" {
		parts := strings.Split(forwarded, ",")
		if len(parts) > 0 {
			if ip := strings.TrimSpace(parts[0]); ip != "" {
				return ip
			}
		}
	}
	if realIP := strings.TrimSpace(r.Header.Get("X-Real-Ip")); realIP != "" {
		return realIP
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err == nil {
		return strings.TrimSpace(host)
	}
	return strings.TrimSpace(r.RemoteAddr)
}

func parseUUIDParam(r *http.Request, key string) (uuid.UUID, error) {
	return uuid.Parse(chi.URLParam(r, key))
}

func intQueryDefault(r *http.Request, key string, fallback int) int {
	value := strings.TrimSpace(r.URL.Query().Get(key))
	if value == "" {
		return fallback
	}
	var parsed int
	if _, err := fmt.Sscanf(value, "%d", &parsed); err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

var roleRank = map[string]int{
	"viewer":    0,
	"user":      1,
	"tech":      2,
	"admin_sec": 3,
	"admin":     4,
	"owner":     5,
}

func canManageRole(actorRole, targetRole string) bool {
	return roleRank[actorRole] > roleRank[targetRole]
}

func canPromoteTo(actorRole, desiredRole string) bool {
	if actorRole == "owner" {
		return true
	}
	if actorRole == "admin" {
		return roleRank[desiredRole] <= roleRank["tech"]
	}
	if actorRole == "admin_sec" {
		return roleRank[desiredRole] <= roleRank["tech"]
	}
	return false
}
