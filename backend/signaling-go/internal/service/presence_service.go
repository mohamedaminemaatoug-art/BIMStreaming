package service

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type PresenceService interface {
	SetDeviceOnline(ctx context.Context, deviceID string, ttl time.Duration) error
	SetDeviceOffline(ctx context.Context, deviceID string) error
	IsDeviceOnline(ctx context.Context, deviceID string) (bool, error)
	Publish(ctx context.Context, channel string, payload string) error
}

type presenceService struct {
	rdb *redis.Client
}

func NewPresenceService(rdb *redis.Client) PresenceService {
	return &presenceService{rdb: rdb}
}

func (s *presenceService) SetDeviceOnline(ctx context.Context, deviceID string, ttl time.Duration) error {
	key := fmt.Sprintf("presence:device:%s", deviceID)
	return s.rdb.Set(ctx, key, "online", ttl).Err()
}

func (s *presenceService) SetDeviceOffline(ctx context.Context, deviceID string) error {
	key := fmt.Sprintf("presence:device:%s", deviceID)
	return s.rdb.Del(ctx, key).Err()
}

func (s *presenceService) IsDeviceOnline(ctx context.Context, deviceID string) (bool, error) {
	key := fmt.Sprintf("presence:device:%s", deviceID)
	v, err := s.rdb.Exists(ctx, key).Result()
	return v > 0, err
}

func (s *presenceService) Publish(ctx context.Context, channel string, payload string) error {
	return s.rdb.Publish(ctx, channel, payload).Err()
}
