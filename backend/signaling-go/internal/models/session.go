package models

import (
	"time"
)

type SessionStatus string

const (
	SessionPending  SessionStatus = "pending"
	SessionActive   SessionStatus = "active"
	SessionEnded    SessionStatus = "ended"
	SessionRejected SessionStatus = "rejected"
)

type Session struct {
	ID             string        `gorm:"primaryKey;type:uuid" json:"id"`
	DeviceFrom     string        `gorm:"index;not null" json:"device_from"`
	DeviceTo       string        `gorm:"index;not null" json:"device_to"`
	Status         SessionStatus `gorm:"type:varchar(20);index;not null" json:"status"`
	StartTime      *time.Time    `json:"start_time"`
	EndTime        *time.Time    `json:"end_time"`
	RelayUsed      bool          `gorm:"default:false" json:"relay_used"`
	BandwidthStats string        `gorm:"type:jsonb;default:'{}'" json:"bandwidth_stats"`
	CreatedAt      time.Time     `json:"created_at"`
	UpdatedAt      time.Time     `json:"updated_at"`
}
