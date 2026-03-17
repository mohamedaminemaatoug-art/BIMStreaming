package models

import "time"

type Device struct {
	ID          string    `gorm:"primaryKey;type:uuid" json:"id"`
	OwnerUserID string    `gorm:"index;not null" json:"owner_user_id"`
	Name        string    `gorm:"not null" json:"name"`
	OS          string    `json:"os"`
	Version     string    `json:"version"`
	IsOnline    bool      `gorm:"default:false" json:"is_online"`
	LastSeenAt  time.Time `gorm:"index" json:"last_seen_at"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}
