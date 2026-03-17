package repository

import (
	"context"

	"bimstreaming/signaling-go/internal/models"
	"gorm.io/gorm"
)

type SessionRepository interface {
	Create(ctx context.Context, s *models.Session) error
	UpdateStatus(ctx context.Context, id string, status models.SessionStatus) error
	GetByID(ctx context.Context, id string) (*models.Session, error)
}

type sessionRepository struct {
	db *gorm.DB
}

func NewSessionRepository(db *gorm.DB) SessionRepository {
	return &sessionRepository{db: db}
}

func (r *sessionRepository) Create(ctx context.Context, s *models.Session) error {
	return r.db.WithContext(ctx).Create(s).Error
}

func (r *sessionRepository) UpdateStatus(ctx context.Context, id string, status models.SessionStatus) error {
	updates := map[string]interface{}{"status": status}
	if status == models.SessionActive {
		updates["start_time"] = gorm.Expr("NOW()")
	}
	if status == models.SessionEnded || status == models.SessionRejected {
		updates["end_time"] = gorm.Expr("NOW()")
	}
	return r.db.WithContext(ctx).Model(&models.Session{}).Where("id = ?", id).Updates(updates).Error
}

func (r *sessionRepository) GetByID(ctx context.Context, id string) (*models.Session, error) {
	var s models.Session
	if err := r.db.WithContext(ctx).First(&s, "id = ?", id).Error; err != nil {
		return nil, err
	}
	return &s, nil
}
