package middleware

import (
	"net/http"
	"strings"

	"bimstreaming/server/internal/auth"
)

func RequireAuth(tokenManager *auth.TokenManager) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			authHeader := strings.TrimSpace(r.Header.Get("Authorization"))
			if authHeader == "" || !strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
				http.Error(w, "missing bearer token", http.StatusUnauthorized)
				return
			}
			token := strings.TrimSpace(authHeader[len("Bearer "):])
			claims, err := tokenManager.ParseAccessToken(token)
			if err != nil {
				http.Error(w, "invalid access token", http.StatusUnauthorized)
				return
			}
			next.ServeHTTP(w, r.WithContext(WithClaims(r.Context(), claims)))
		})
	}
}
