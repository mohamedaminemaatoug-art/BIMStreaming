package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/config"
	"bimstreaming/server/internal/db"
	"bimstreaming/server/internal/email"
	"bimstreaming/server/internal/geoip"
	"bimstreaming/server/internal/handlers"
	"bimstreaming/server/internal/middleware"
	"bimstreaming/server/internal/push"
	"bimstreaming/server/internal/repository"
	"bimstreaming/server/internal/storage"
	"bimstreaming/server/internal/worker"
	wshub "bimstreaming/server/internal/ws"

	"github.com/go-chi/chi/v5"
	"github.com/joho/godotenv"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Printf("warning: could not load .env file: %v", err)
	}

	if shouldRunMigrations(os.Args[1:]) {
		databaseURL := os.Getenv("DATABASE_URL")
		if databaseURL == "" {
			databaseURL = os.Getenv("envDATABASE_URL")
		}
		if databaseURL == "" {
			log.Fatalf("invalid configuration: DATABASE_URL is required for migration")
		}

		database, err := db.Connect(databaseURL)
		if err != nil {
			log.Fatalf("database connection failed: %v", err)
		}
		defer database.Close()

		if err := runMigrations(context.Background(), database, "migrations"); err != nil {
			log.Fatalf("migration failed: %v", err)
		}

		log.Print("migrations complete")
		os.Exit(0)
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("invalid configuration: %v", err)
	}
	database, err := db.Connect(cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("database connection failed: %v", err)
	}
	defer database.Close()

	clients := NewClientRegistry()
	sessions := NewSessionRegistry()
	repo := repository.New(database)
	tokens := auth.NewTokenManager(cfg.JWTSecret, cfg.JWTRefreshSecret)
	hub := wshub.NewHub()
	wsRouter := NewRouter(clients, sessions, repo, tokens, hub)
	emailSender := email.NewSender(cfg.SMTPHost, cfg.SMTPPort, cfg.SMTPUser, cfg.SMTPPass, cfg.SMTPFrom)
	if err := emailSender.VerifyTemplates(); err != nil {
		log.Fatalf("email template verification failed: %v", err)
	}
	geoIP := geoip.New()
	planEnforcer := middleware.NewPlanEnforcer(repo)
	fcmSender := push.NewFCMSender(cfg.FCMServerKey, cfg.FCMEndpoint)
	pushDispatcher := push.NewDispatcher(repo, fcmSender, 256)
	pushDispatcher.Start(context.Background())
	avatarService := storage.NewAvatarService(cfg.AvatarStoragePath, cfg.AppBaseURL, cfg.MaxUploadSizeMB)
	if err := avatarService.EnsureStorage(); err != nil {
		log.Fatalf("failed to ensure avatar storage: %v", err)
	}
	attachmentService := storage.NewAttachmentService(cfg.AvatarStoragePath+"/attachments", cfg.AppBaseURL, cfg.MaxUploadSizeMB)
	if err := attachmentService.EnsureStorage(); err != nil {
		log.Fatalf("failed to ensure attachment storage: %v", err)
	}
	app, err := handlers.New(repo, tokens, emailSender, geoIP, avatarService, attachmentService, hub, pushDispatcher, cfg.AppBaseURL, cfg.EncryptionKey)
	if err != nil {
		log.Fatalf("failed to initialize app: %v", err)
	}
	worker.StartCleanupLoop(context.Background(), repo)

	rateLimiter := middleware.NewRateLimiter()
	r := chi.NewRouter()
	r.Use(middleware.RequestLogger)
	r.Get("/api/v1/ws", wsRouter.HandleWS)
	app.Mount(r, middleware.RequireAuth(tokens), rateLimiter.Middleware(cfg.RateLimitEnabled), planEnforcer)

	log.Printf("relay+api server listening on %s", cfg.ServerAddr)
	if err := http.ListenAndServe(cfg.ServerAddr, r); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
