package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"bimstreaming/signaling-go/internal/config"
	"bimstreaming/signaling-go/internal/handler"
	"bimstreaming/signaling-go/internal/middleware"
	"bimstreaming/signaling-go/internal/models"
	"bimstreaming/signaling-go/internal/repository"
	"bimstreaming/signaling-go/internal/service"
	ws "bimstreaming/signaling-go/internal/websocket"
	"bimstreaming/signaling-go/pkg/logger"
	"bimstreaming/signaling-go/pkg/metrics"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/redis/go-redis/v9"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func main() {
	cfg := config.Load()
	log := logger.New()

	db, err := gorm.Open(postgres.Open(cfg.PostgresDSN), &gorm.Config{})
	if err != nil {
		panic(err)
	}
	if err := db.AutoMigrate(&models.Device{}, &models.Session{}); err != nil {
		panic(err)
	}

	rdb := redis.NewClient(&redis.Options{
		Addr:     cfg.RedisAddr,
		Password: cfg.RedisPassword,
		DB:       cfg.RedisDB,
	})

	deviceRepo := repository.NewDeviceRepository(db)
	sessionRepo := repository.NewSessionRepository(db)
	presenceSvc := service.NewPresenceService(rdb)
	deviceSvc := service.NewDeviceService(deviceRepo, presenceSvc)
	sessionSvc := service.NewSessionService(sessionRepo)
	iceSvc := service.NewICEService(cfg.StunURL, cfg.TurnURL, cfg.TurnUsername, cfg.TurnPassword)

	hub := ws.NewHub(presenceSvc)
	wsHandler := handler.NewWSHandler(hub, cfg.WSReadBuffer, cfg.WSWriteBuffer)
	compatHandler := handler.NewSignalingCompatHandler(sessionSvc, hub)
	deviceHandler := handler.NewDeviceHandler(deviceSvc)
	sessionHandler := handler.NewSessionHandler(sessionSvc)
	iceHandler := handler.NewICEHandler(iceSvc)

	jwtValidator, jwtErr := middleware.NewJWTValidator(cfg.KeycloakIssuer, cfg.KeycloakAudience, cfg.KeycloakJWKSURL)
	devMode := strings.EqualFold(os.Getenv("APP_ENV"), "development")

	metrics.Register()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", handler.Health)
	mux.Handle("/metrics", promhttp.Handler())

	// Compatibility endpoints used by the current Flutter client.
	mux.HandleFunc("/ws", wsHandler.ServeWS)
	mux.HandleFunc("/session/request", compatHandler.Request)
	mux.HandleFunc("/session/respond", compatHandler.Respond)

	protectedBase := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/api/v1/devices/register":
			if r.Method == http.MethodPost {
				deviceHandler.Register(w, r)
				return
			}
		case "/api/v1/ws":
			wsHandler.ServeWS(w, r)
			return
		case "/api/v1/sessions/create":
			sessionHandler.Create(w, r)
			return
		case "/api/v1/sessions/accept":
			sessionHandler.Accept(w, r)
			return
		case "/api/v1/sessions/reject":
			sessionHandler.Reject(w, r)
			return
		case "/api/v1/sessions/end":
			sessionHandler.End(w, r)
			return
		case "/api/v1/ice-servers":
			iceHandler.GetICEServers(w, r)
			return
		}
		http.NotFound(w, r)
	})

	var protected http.Handler
	if jwtErr != nil {
		if devMode {
			log.Error("jwt validator unavailable, running in dev permissive mode", "err", jwtErr)
			protected = protectedBase
		} else {
			panic(jwtErr)
		}
	} else {
		protected = jwtValidator.Middleware(protectedBase)
	}

	mux.Handle("/api/v1/", middleware.RateLimit(cfg.RateLimitRPS, cfg.RateLimitBurst)(protected))

	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", cfg.AppPort),
		Handler:      mux,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  30 * time.Second,
	}

	go func() {
		log.Info("server started", "port", cfg.AppPort)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Error("server error", "err", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	ctx, cancel := context.WithTimeout(context.Background(), cfg.GracefulTimeout)
	defer cancel()
	_ = server.Shutdown(ctx)
	log.Info("server stopped")
}
