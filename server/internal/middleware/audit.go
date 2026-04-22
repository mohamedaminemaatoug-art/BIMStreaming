package middleware

import (
	"net"
	"net/http"
	"strings"
	"time"

	"bimstreaming/server/internal/models"
	"bimstreaming/server/internal/repository"

	"github.com/google/uuid"
)

type auditResponseWriter struct {
	http.ResponseWriter
	status int
}

func (w *auditResponseWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func Audit(repo *repository.Repository) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			writer := &auditResponseWriter{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(writer, r)
			claims, ok := ClaimsFromContext(r.Context())
			if !ok || repo == nil {
				return
			}
			if writer.status < http.StatusBadRequest && r.Method == http.MethodGet && !strings.HasPrefix(r.URL.Path, "/api/v1/admin") && !strings.HasPrefix(r.URL.Path, "/api/v1/security") {
				return
			}
			userID, err := uuid.Parse(claims.RegisteredClaims.Subject)
			if err != nil {
				return
			}
			_ = repo.InsertAuditLog(r.Context(), models.AuditLog{
				ID:           uuid.New(),
				UserID:       uuid.NullUUID{UUID: userID, Valid: true},
				Action:       "http_" + strings.ToLower(r.Method),
				ResourceType: strings.TrimPrefix(r.URL.Path, "/"),
				ResourceID:   "",
				IPAddress:    auditClientIP(r),
				UserAgent:    r.UserAgent(),
				Metadata:     []byte(time.Now().UTC().Format(time.RFC3339)),
			})
		})
	}
}

func auditClientIP(r *http.Request) string {
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
