package repository

import (
	"context"

	"bimstreaming/signaling-go/internal/models"
	"gorm.io/gorm"
)

type DeviceRepository interface {
	Upsert(ctx context.Context, d *models.Device) error
	SetOnline(ctx context.Context, id string, online bool) error
	GetByID(ctx context.Context, id string) (*models.Device, error)
}

type deviceRepository struct {
	db *gorm.DB
}

func NewDeviceRepository(db *gorm.DB) DeviceRepository {
	return &deviceRepository{db: db}
}

func (r *deviceRepository) Upsert(ctx context.Context, d *models.Device) error {
	return r.db.WithContext(ctx).Save(d).Error
}

func (r *deviceRepository) SetOnline(ctx context.Context, id string, online bool) error {
	return r.db.WithContext(ctx).Model(&models.Device{}).Where("id = ?", id).Updates(map[string]interface{}{
		"is_online":    online,
		"last_seen_at": gorm.Expr("NOW()"),
	}).Error
}

func (r *deviceRepository) GetByID(ctx context.Context, id string) (*models.Device, error) {
	var d models.Device
	if err := r.db.WithContext(ctx).First(&d, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &d, nil
}
