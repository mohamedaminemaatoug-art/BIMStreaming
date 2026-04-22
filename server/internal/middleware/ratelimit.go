package middleware

import (
	"net"
	"net/http"
	"strconv"
	"sync"
	"time"
)

type limiterRule struct {
	limit  int
	window time.Duration
}

type bucket struct {
	timestamps []time.Time
}

type RateLimiter struct {
	mu    sync.Mutex
	data  map[string]*bucket
	rules map[string]limiterRule
}

func NewRateLimiter() *RateLimiter {
	rl := &RateLimiter{
		data: make(map[string]*bucket),
		rules: map[string]limiterRule{
			"/api/v1/auth/login":               {limit: 10, window: 15 * time.Minute},
			"/api/v1/auth/forgot-password":     {limit: 3, window: time.Hour},
			"/api/v1/auth/resend-verification": {limit: 1, window: time.Minute},
		},
	}
	go rl.cleanupLoop()
	return rl
}

func (rl *RateLimiter) Middleware(enabled bool) func(http.Handler) http.Handler {
	if !enabled {
		return func(next http.Handler) http.Handler { return next }
	}
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			rule, ok := rl.rules[r.URL.Path]
			if !ok {
				next.ServeHTTP(w, r)
				return
			}
			ip := clientIP(r)
			key := r.URL.Path + "|" + ip
			allowed, retryAfter := rl.allow(key, rule)
			if !allowed {
				w.Header().Set("Retry-After", strconv.Itoa(int(retryAfter.Seconds())))
				http.Error(w, "rate limit exceeded", http.StatusTooManyRequests)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

func (rl *RateLimiter) allow(key string, rule limiterRule) (bool, time.Duration) {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	now := time.Now().UTC()
	b, ok := rl.data[key]
	if !ok {
		b = &bucket{timestamps: []time.Time{}}
		rl.data[key] = b
	}
	threshold := now.Add(-rule.window)
	filtered := b.timestamps[:0]
	for _, t := range b.timestamps {
		if t.After(threshold) {
			filtered = append(filtered, t)
		}
	}
	b.timestamps = filtered
	if len(b.timestamps) >= rule.limit {
		retryAfter := b.timestamps[0].Add(rule.window).Sub(now)
		if retryAfter < 0 {
			retryAfter = 0
		}
		return false, retryAfter
	}
	b.timestamps = append(b.timestamps, now)
	return true, 0
}

func (rl *RateLimiter) cleanupLoop() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		rl.mu.Lock()
		now := time.Now().UTC()
		for key, b := range rl.data {
			latest := time.Time{}
			for _, t := range b.timestamps {
				if t.After(latest) {
					latest = t
				}
			}
			if !latest.IsZero() && now.Sub(latest) > 2*time.Hour {
				delete(rl.data, key)
			}
		}
		rl.mu.Unlock()
	}
}

func clientIP(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		return forwarded
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
