package middleware

import (
	"context"

	"bimstreaming/server/internal/auth"
)

type contextKey string

const AccessClaimsKey contextKey = "access_claims"

func WithClaims(ctx context.Context, claims *auth.AccessClaims) context.Context {
	return context.WithValue(ctx, AccessClaimsKey, claims)
}

func ClaimsFromContext(ctx context.Context) (*auth.AccessClaims, bool) {
	claims, ok := ctx.Value(AccessClaimsKey).(*auth.AccessClaims)
	return claims, ok
}
