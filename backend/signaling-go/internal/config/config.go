package config

import (
	"os"
	"strconv"
	"time"
)

type Config struct {
	AppPort         string
	GracefulTimeout time.Duration

	PostgresDSN string

	RedisAddr     string
	RedisPassword string
	RedisDB       int

	KeycloakIssuer   string
	KeycloakAudience string
	KeycloakJWKSURL  string

	TurnURL      string
	TurnUsername string
	TurnPassword string
	StunURL      string

	RateLimitRPS   int
	RateLimitBurst int

	WSReadBuffer  int
	WSWriteBuffer int
}

func Load() Config {
	return Config{
		AppPort:         getEnv("APP_PORT", "8080"),
		GracefulTimeout: mustDuration(getEnv("APP_GRACEFUL_TIMEOUT", "10s")),

		PostgresDSN: getEnv("POSTGRES_DSN", "host=localhost user=postgres password=postgres dbname=bimstream sslmode=disable"),

		RedisAddr:     getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),
		RedisDB:       mustInt(getEnv("REDIS_DB", "0")),

		KeycloakIssuer:   getEnv("KEYCLOAK_ISSUER", "http://localhost:8081/realms/bim"),
		KeycloakAudience: getEnv("KEYCLOAK_AUDIENCE", "bim-backend"),
		KeycloakJWKSURL:  getEnv("KEYCLOAK_JWKS_URL", "http://localhost:8081/realms/bim/protocol/openid-connect/certs"),

		TurnURL:      getEnv("TURN_URL", "turn:localhost:3478?transport=udp"),
		TurnUsername: getEnv("TURN_USERNAME", "bimturn"),
		TurnPassword: getEnv("TURN_PASSWORD", "turnpassword"),
		StunURL:      getEnv("STUN_URL", "stun:localhost:3478"),

		RateLimitRPS:   mustInt(getEnv("RATE_LIMIT_RPS", "20")),
		RateLimitBurst: mustInt(getEnv("RATE_LIMIT_BURST", "40")),

		WSReadBuffer:  mustInt(getEnv("WS_READ_BUFFER", "2048")),
		WSWriteBuffer: mustInt(getEnv("WS_WRITE_BUFFER", "2048")),
	}
}

func getEnv(key, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}

func mustInt(v string) int {
	i, err := strconv.Atoi(v)
	if err != nil {
		return 0
	}
	return i
}

func mustDuration(v string) time.Duration {
	d, err := time.ParseDuration(v)
	if err != nil {
		return 10 * time.Second
	}
	return d
}
