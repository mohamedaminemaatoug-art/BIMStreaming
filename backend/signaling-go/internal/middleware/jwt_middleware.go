package middleware

import (
	"context"
	"net/http"
	"strings"

	"github.com/MicahParks/keyfunc/v2"
	"github.com/golang-jwt/jwt/v5"
)

type Claims struct {
	Roles []string `json:"roles,omitempty"`
	jwt.RegisteredClaims
}

type ctxKey string

const ClaimsKey ctxKey = "claims"

type JWTValidator struct {
	issuer   string
	audience string
	jwks     *keyfunc.JWKS
}

func NewJWTValidator(issuer, audience, jwksURL string) (*JWTValidator, error) {
	jwks, err := keyfunc.Get(jwksURL, keyfunc.Options{})
	if err != nil {
		return nil, err
	}
	return &JWTValidator{issuer: issuer, audience: audience, jwks: jwks}, nil
}

func (v *JWTValidator) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			http.Error(w, "missing bearer token", http.StatusUnauthorized)
			return
		}
		tokenString := strings.TrimPrefix(auth, "Bearer ")

		claims := &Claims{}
		token, err := jwt.ParseWithClaims(tokenString, claims, v.jwks.Keyfunc)
		if err != nil || !token.Valid {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}
		if claims.Issuer != v.issuer {
			http.Error(w, "invalid issuer", http.StatusUnauthorized)
			return
		}
		audienceOK := false
		for _, aud := range claims.Audience {
			if aud == v.audience {
				audienceOK = true
				break
			}
		}
		if !audienceOK {
			http.Error(w, "invalid audience", http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), ClaimsKey, claims)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func RequireRole(role string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		claims, ok := r.Context().Value(ClaimsKey).(*Claims)
		if !ok {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		for _, userRole := range claims.Roles {
			if userRole == role {
				next.ServeHTTP(w, r)
				return
			}
		}
		http.Error(w, "forbidden", http.StatusForbidden)
	})
}
