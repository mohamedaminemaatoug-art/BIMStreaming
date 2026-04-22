package config

import (
	"fmt"
	"os"
	"strconv"
)

type Config struct {
	ServerAddr        string
	DatabaseURL       string
	JWTSecret         string
	JWTRefreshSecret  string
	EncryptionKey     string
	SMTPHost          string
	SMTPPort          int
	SMTPUser          string
	SMTPPass          string
	SMTPFrom          string
	FCMServerKey      string
	FCMEndpoint       string
	AppBaseURL        string
	AvatarStoragePath string
	MaxUploadSizeMB   int64
	RateLimitEnabled  bool
}

func Load() (*Config, error) {
	cfg := &Config{
		ServerAddr:        getEnv("SERVER_ADDR", ":8080"),
		DatabaseURL:       os.Getenv("DATABASE_URL"),
		JWTSecret:         os.Getenv("JWT_SECRET"),
		JWTRefreshSecret:  os.Getenv("JWT_REFRESH_SECRET"),
		EncryptionKey:     os.Getenv("ENCRYPTION_KEY"),
		SMTPHost:          os.Getenv("SMTP_HOST"),
		SMTPPort:          getEnvAsInt("SMTP_PORT", 587),
		SMTPUser:          firstNonEmpty(os.Getenv("SMTP_USER"), os.Getenv("SMTP__USER")),
		SMTPPass:          os.Getenv("SMTP_PASS"),
		SMTPFrom:          getEnv("SMTP_FROM", "noreply@bim-streaming.com"),
		FCMServerKey:      os.Getenv("FCM_SERVER_KEY"),
		FCMEndpoint:       getEnv("FCM_ENDPOINT", "https://fcm.googleapis.com/fcm/send"),
		AppBaseURL:        getEnv("APP_BASE_URL", "http://localhost:8080"),
		AvatarStoragePath: getEnv("AVATAR_STORAGE_PATH", "./storage/avatars"),
		MaxUploadSizeMB:   int64(getEnvAsInt("MAX_UPLOAD_SIZE_MB", 5)),
		RateLimitEnabled:  getEnvAsBool("RATE_LIMIT_ENABLED", true),
	}

	if cfg.DatabaseURL == "" {
		return nil, fmt.Errorf("DATABASE_URL is required")
	}
	if cfg.JWTSecret == "" {
		return nil, fmt.Errorf("JWT_SECRET is required")
	}
	if cfg.JWTRefreshSecret == "" {
		return nil, fmt.Errorf("JWT_REFRESH_SECRET is required")
	}
	if cfg.EncryptionKey == "" {
		return nil, fmt.Errorf("ENCRYPTION_KEY is required")
	}
	return cfg, nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getEnvAsInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func getEnvAsBool(key string, fallback bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return fallback
	}
	return parsed
}
