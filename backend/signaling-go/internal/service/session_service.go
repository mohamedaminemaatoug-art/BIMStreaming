package service

import (
	"context"

	"bimstreaming/signaling-go/internal/models"
	"bimstreaming/signaling-go/internal/repository"
	"github.com/google/uuid"
)

type SessionService interface {
	CreatePending(ctx context.Context, fromDevice, toDevice string) (*models.Session, error)
	Accept(ctx context.Context, sessionID string) error
	Reject(ctx context.Context, sessionID string) error
	End(ctx context.Context, sessionID string) error
}

type sessionService struct {
	repo repository.SessionRepository
}

func NewSessionService(repo repository.SessionRepository) SessionService {
	return &sessionService{repo: repo}
}

func (s *sessionService) CreatePending(ctx context.Context, fromDevice, toDevice string) (*models.Session, error) {
	session := &models.Session{
		ID:         uuid.NewString(),
		DeviceFrom: fromDevice,
		DeviceTo:   toDevice,
		Status:     models.SessionPending,
	}
	if err := s.repo.Create(ctx, session); err != nil {
		return nil, err
	}
	return session, nil
}

func (s *sessionService) Accept(ctx context.Context, sessionID string) error {
	return s.repo.UpdateStatus(ctx, sessionID, models.SessionActive)
}

func (s *sessionService) Reject(ctx context.Context, sessionID string) error {
	return s.repo.UpdateStatus(ctx, sessionID, models.SessionRejected)
}

func (s *sessionService) End(ctx context.Context, sessionID string) error {
	return s.repo.UpdateStatus(ctx, sessionID, models.SessionEnded)
}
