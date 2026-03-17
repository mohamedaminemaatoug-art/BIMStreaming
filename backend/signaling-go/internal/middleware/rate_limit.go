package middleware

import (
	"net/http"
	"sync"
	"time"
)

type tokenBucket struct {
	tokens     float64
	lastRefill time.Time
}

func RateLimit(rps int, burst int) func(http.Handler) http.Handler {
	var (
		mu      sync.Mutex
		buckets = map[string]*tokenBucket{}
	)

	refill := func(b *tokenBucket) {
		now := time.Now()
		delta := now.Sub(b.lastRefill).Seconds() * float64(rps)
		b.tokens += delta
		if b.tokens > float64(burst) {
			b.tokens = float64(burst)
		}
		b.lastRefill = now
	}

	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			ip := r.RemoteAddr
			mu.Lock()
			b, ok := buckets[ip]
			if !ok {
				b = &tokenBucket{tokens: float64(burst), lastRefill: time.Now()}
				buckets[ip] = b
			}
			refill(b)
			if b.tokens < 1 {
				mu.Unlock()
				http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
				return
			}
			b.tokens -= 1
			mu.Unlock()
			next.ServeHTTP(w, r)
		})
	}
}
