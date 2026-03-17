package service

import (
	"context"
	"time"

	"bimstreaming/signaling-go/internal/models"
	"bimstreaming/signaling-go/internal/repository"
)

type DeviceService interface {
	Register(ctx context.Context, d *models.Device) error
	MarkOnline(ctx context.Context, deviceID string) error
	MarkOffline(ctx context.Context, deviceID string) error
}

type deviceService struct {
	repo     repository.DeviceRepository
	presence PresenceService
}

func NewDeviceService(repo repository.DeviceRepository, presence PresenceService) DeviceService {
	return &deviceService{repo: repo, presence: presence}
}

func (s *deviceService) Register(ctx context.Context, d *models.Device) error {
	d.LastSeenAt = time.Now().UTC()
	return s.repo.Upsert(ctx, d)
}

func (s *deviceService) MarkOnline(ctx context.Context, deviceID string) error {
	if err := s.repo.SetOnline(ctx, deviceID, true); err != nil {
		return err
	}
	return s.presence.SetDeviceOnline(ctx, deviceID, 30*time.Second)
}

func (s *deviceService) MarkOffline(ctx context.Context, deviceID string) error {
	if err := s.repo.SetOnline(ctx, deviceID, false); err != nil {
		return err
	}
	return s.presence.SetDeviceOffline(ctx, deviceID)
}
