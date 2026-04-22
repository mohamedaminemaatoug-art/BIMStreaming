package models

import (
	"database/sql"
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID                      uuid.UUID      `db:"id" json:"id"`
	Username                string         `db:"username" json:"username"`
	Email                   string         `db:"email" json:"email"`
	Phone                   sql.NullString `db:"phone" json:"phone"`
	PasswordHash            string         `db:"password_hash" json:"-"`
	AvatarURL               sql.NullString `db:"avatar_url" json:"avatar_url"`
	DeviceID                string         `db:"device_id" json:"device_id"`
	DeviceAlias             sql.NullString `db:"device_alias" json:"device_alias"`
	DisplayName             sql.NullString `db:"display_name" json:"display_name"`
	Bio                     sql.NullString `db:"bio" json:"bio"`
	Language                string         `db:"language" json:"language"`
	Timezone                string         `db:"timezone" json:"timezone"`
	Theme                   string         `db:"theme" json:"theme"`
	NotificationPreferences []byte         `db:"notification_preferences" json:"notification_preferences"`
	TwoFactorEnabled        bool           `db:"two_factor_enabled" json:"two_factor_enabled"`
	TwoFactorSecret         sql.NullString `db:"two_factor_secret" json:"-"`
	IsVerified              bool           `db:"is_verified" json:"is_verified"`
	IsOnline                bool           `db:"is_online" json:"is_online"`
	LockedUntil             sql.NullTime   `db:"locked_until" json:"locked_until"`
	FailedLoginCount        int            `db:"failed_login_count" json:"failed_login_count"`
	LastFailedLoginAt       sql.NullTime   `db:"last_failed_login_at" json:"last_failed_login_at"`
	IsBanned                bool           `db:"is_banned" json:"is_banned"`
	BanReason               sql.NullString `db:"ban_reason" json:"ban_reason"`
	IsSuperadmin            bool           `db:"is_superadmin" json:"is_superadmin"`
	LastSeenAt              sql.NullTime   `db:"last_seen_at" json:"last_seen_at"`
	CreatedAt               time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt               time.Time      `db:"updated_at" json:"updated_at"`
	DeletedAt               sql.NullTime   `db:"deleted_at" json:"-"`
}

type EmailVerification struct {
	ID        uuid.UUID    `db:"id"`
	UserID    uuid.UUID    `db:"user_id"`
	Token     string       `db:"token"`
	ExpiresAt time.Time    `db:"expires_at"`
	UsedAt    sql.NullTime `db:"used_at"`
	CreatedAt time.Time    `db:"created_at"`
	UpdatedAt time.Time    `db:"updated_at"`
}

type PasswordReset struct {
	ID        uuid.UUID    `db:"id"`
	UserID    uuid.UUID    `db:"user_id"`
	TokenHash string       `db:"token_hash"`
	ExpiresAt time.Time    `db:"expires_at"`
	UsedAt    sql.NullTime `db:"used_at"`
	CreatedAt time.Time    `db:"created_at"`
	UpdatedAt time.Time    `db:"updated_at"`
}

type RefreshToken struct {
	ID                uuid.UUID      `db:"id"`
	UserID            uuid.UUID      `db:"user_id"`
	TokenHash         string         `db:"token_hash"`
	DeviceFingerprint sql.NullString `db:"device_fingerprint"`
	ExpiresAt         time.Time      `db:"expires_at"`
	RevokedAt         sql.NullTime   `db:"revoked_at"`
	CreatedAt         time.Time      `db:"created_at"`
	UpdatedAt         time.Time      `db:"updated_at"`
}

type DeviceSession struct {
	ID              uuid.UUID      `db:"id" json:"id"`
	UserID          uuid.UUID      `db:"user_id" json:"user_id"`
	DeviceID        string         `db:"device_id" json:"device_id"`
	SessionPassword string         `db:"session_password" json:"session_password"`
	Label           sql.NullString `db:"label" json:"label"`
	IsActive        bool           `db:"is_active" json:"is_active"`
	LastActiveAt    sql.NullTime   `db:"last_active_at" json:"last_active_at"`
	CreatedAt       time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt       time.Time      `db:"updated_at" json:"updated_at"`
}

type Community struct {
	ID          uuid.UUID      `db:"id" json:"id"`
	Code        string         `db:"code" json:"code"`
	Name        string         `db:"name" json:"name"`
	Description sql.NullString `db:"description" json:"description"`
	Country     sql.NullString `db:"country" json:"country"`
	AvatarURL   sql.NullString `db:"avatar_url" json:"avatar_url"`
	OwnerID     uuid.UUID      `db:"owner_id" json:"owner_id"`
	IsPublic    bool           `db:"is_public" json:"is_public"`
	CreatedAt   time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time      `db:"updated_at" json:"updated_at"`
	DeletedAt   sql.NullTime   `db:"deleted_at" json:"-"`
}

type Department struct {
	ID          uuid.UUID      `db:"id" json:"id"`
	CommunityID uuid.UUID      `db:"community_id" json:"community_id"`
	Name        string         `db:"name" json:"name"`
	Country     sql.NullString `db:"country" json:"country"`
	CreatedAt   time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time      `db:"updated_at" json:"updated_at"`
	DeletedAt   sql.NullTime   `db:"deleted_at" json:"-"`
}

type CommunityMember struct {
	ID           uuid.UUID     `db:"id" json:"id"`
	CommunityID  uuid.UUID     `db:"community_id" json:"community_id"`
	UserID       uuid.UUID     `db:"user_id" json:"user_id"`
	DepartmentID uuid.NullUUID `db:"department_id" json:"department_id"`
	Role         string        `db:"role" json:"role"`
	JoinedAt     time.Time     `db:"joined_at" json:"joined_at"`
	InvitedBy    uuid.NullUUID `db:"invited_by" json:"invited_by"`
	Status       string        `db:"status" json:"status"`
	CreatedAt    time.Time     `db:"created_at" json:"created_at"`
	UpdatedAt    time.Time     `db:"updated_at" json:"updated_at"`
	DeletedAt    sql.NullTime  `db:"deleted_at" json:"-"`
}

type JoinRequest struct {
	ID             uuid.UUID      `db:"id" json:"id"`
	CommunityID    uuid.UUID      `db:"community_id" json:"community_id"`
	UserID         uuid.UUID      `db:"user_id" json:"user_id"`
	InviteCodeUsed sql.NullString `db:"invite_code_used" json:"invite_code_used"`
	Message        sql.NullString `db:"message" json:"message"`
	Status         string         `db:"status" json:"status"`
	ReviewedBy     uuid.NullUUID  `db:"reviewed_by" json:"reviewed_by"`
	ReviewedAt     sql.NullTime   `db:"reviewed_at" json:"reviewed_at"`
	CreatedAt      time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt      time.Time      `db:"updated_at" json:"updated_at"`
}

type Friendship struct {
	ID          uuid.UUID    `db:"id" json:"id"`
	RequesterID uuid.UUID    `db:"requester_id" json:"requester_id"`
	AddresseeID uuid.UUID    `db:"addressee_id" json:"addressee_id"`
	Status      string       `db:"status" json:"status"`
	CreatedAt   time.Time    `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time    `db:"updated_at" json:"updated_at"`
	DeletedAt   sql.NullTime `db:"deleted_at" json:"-"`
}

type DirectMessage struct {
	ID          uuid.UUID     `db:"id" json:"id"`
	SenderID    uuid.UUID     `db:"sender_id" json:"sender_id"`
	RecipientID uuid.UUID     `db:"recipient_id" json:"recipient_id"`
	ReplyToID   uuid.NullUUID `db:"reply_to_id" json:"reply_to_id"`
	Content     string        `db:"content" json:"content"`
	IsRead      bool          `db:"is_read" json:"is_read"`
	IsEdited    bool          `db:"is_edited" json:"is_edited"`
	IsDeleted   bool          `db:"is_deleted" json:"is_deleted"`
	EditedAt    sql.NullTime  `db:"edited_at" json:"edited_at"`
	ReadAt      sql.NullTime  `db:"read_at" json:"read_at"`
	CreatedAt   time.Time     `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time     `db:"updated_at" json:"updated_at"`
}

type CommunityMessage struct {
	ID          uuid.UUID     `db:"id" json:"id"`
	CommunityID uuid.UUID     `db:"community_id" json:"community_id"`
	SenderID    uuid.UUID     `db:"sender_id" json:"sender_id"`
	ReplyToID   uuid.NullUUID `db:"reply_to_id" json:"reply_to_id"`
	Content     string        `db:"content" json:"content"`
	IsEdited    bool          `db:"is_edited" json:"is_edited"`
	IsDeleted   bool          `db:"is_deleted" json:"is_deleted"`
	EditedAt    sql.NullTime  `db:"edited_at" json:"edited_at"`
	CreatedAt   time.Time     `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time     `db:"updated_at" json:"updated_at"`
}

type Notification struct {
	ID        uuid.UUID `db:"id" json:"id"`
	UserID    uuid.UUID `db:"user_id" json:"user_id"`
	Type      string    `db:"type" json:"type"`
	Payload   []byte    `db:"payload" json:"payload"`
	IsRead    bool      `db:"is_read" json:"is_read"`
	CreatedAt time.Time `db:"created_at" json:"created_at"`
	UpdatedAt time.Time `db:"updated_at" json:"updated_at"`
}

type RemoteSessionInvite struct {
	ID             uuid.UUID      `db:"id" json:"id"`
	RequesterID    uuid.UUID      `db:"requester_id" json:"requester_id"`
	TargetDeviceID string         `db:"target_device_id" json:"target_device_id"`
	Status         string         `db:"status" json:"status"`
	SessionToken   sql.NullString `db:"session_token" json:"session_token"`
	ExpiresAt      time.Time      `db:"expires_at" json:"expires_at"`
	CreatedAt      time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt      time.Time      `db:"updated_at" json:"updated_at"`
}

type ActivityLog struct {
	ID              uuid.UUID     `db:"id" json:"id"`
	UserID          uuid.UUID     `db:"user_id" json:"user_id"`
	TargetUsername  string        `db:"target_username" json:"target_username"`
	TargetDeviceID  string        `db:"target_device_id" json:"target_device_id"`
	SessionType     string        `db:"session_type" json:"session_type"`
	DurationSeconds sql.NullInt32 `db:"duration_seconds" json:"duration_seconds"`
	Status          string        `db:"status" json:"status"`
	StartedAt       time.Time     `db:"started_at" json:"started_at"`
	EndedAt         sql.NullTime  `db:"ended_at" json:"ended_at"`
	CreatedAt       time.Time     `db:"created_at" json:"created_at"`
	UpdatedAt       time.Time     `db:"updated_at" json:"updated_at"`
}

type TOTpBackupCode struct {
	ID        uuid.UUID    `db:"id" json:"id"`
	UserID    uuid.UUID    `db:"user_id" json:"user_id"`
	CodeHash  string       `db:"code_hash" json:"-"`
	UsedAt    sql.NullTime `db:"used_at" json:"used_at"`
	CreatedAt time.Time    `db:"created_at" json:"created_at"`
}

type AuditLog struct {
	ID           uuid.UUID     `db:"id" json:"id"`
	UserID       uuid.NullUUID `db:"user_id" json:"user_id"`
	Action       string        `db:"action" json:"action"`
	ResourceType string        `db:"resource_type" json:"resource_type"`
	ResourceID   string        `db:"resource_id" json:"resource_id"`
	IPAddress    string        `db:"ip_address" json:"ip_address"`
	UserAgent    string        `db:"user_agent" json:"user_agent"`
	Metadata     []byte        `db:"metadata" json:"metadata"`
	CreatedAt    time.Time     `db:"created_at" json:"created_at"`
}

type LoginHistory struct {
	ID                uuid.UUID      `db:"id" json:"id"`
	UserID            uuid.UUID      `db:"user_id" json:"user_id"`
	IPAddress         string         `db:"ip_address" json:"ip_address"`
	Country           sql.NullString `db:"country" json:"country"`
	City              sql.NullString `db:"city" json:"city"`
	DeviceFingerprint string         `db:"device_fingerprint" json:"device_fingerprint"`
	OS                string         `db:"os" json:"os"`
	AppVersion        string         `db:"app_version" json:"app_version"`
	Status            string         `db:"status" json:"status"`
	FailureReason     sql.NullString `db:"failure_reason" json:"failure_reason"`
	CreatedAt         time.Time      `db:"created_at" json:"created_at"`
}

type TrustedDevice struct {
	ID                uuid.UUID      `db:"id" json:"id"`
	UserID            uuid.UUID      `db:"user_id" json:"user_id"`
	DeviceFingerprint string         `db:"device_fingerprint" json:"device_fingerprint"`
	DeviceName        sql.NullString `db:"device_name" json:"device_name"`
	LastUsedAt        sql.NullTime   `db:"last_used_at" json:"last_used_at"`
	TrustedAt         time.Time      `db:"trusted_at" json:"trusted_at"`
	RevokedAt         sql.NullTime   `db:"revoked_at" json:"revoked_at"`
	CreatedAt         time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt         time.Time      `db:"updated_at" json:"updated_at"`
}

type UserStatus struct {
	ID           uuid.UUID      `db:"id" json:"id"`
	UserID       uuid.UUID      `db:"user_id" json:"user_id"`
	Emoji        sql.NullString `db:"emoji" json:"emoji"`
	Message      sql.NullString `db:"message" json:"message"`
	Availability string         `db:"availability" json:"availability"`
	ExpiresAt    sql.NullTime   `db:"expires_at" json:"expires_at"`
	UpdatedAt    time.Time      `db:"updated_at" json:"updated_at"`
	CreatedAt    time.Time      `db:"created_at" json:"created_at"`
}

type RemoteSession struct {
	ID              uuid.UUID      `db:"id" json:"id"`
	InviteID        uuid.NullUUID  `db:"invite_id" json:"invite_id"`
	ControllerID    uuid.UUID      `db:"controller_id" json:"controller_id"`
	HostID          uuid.UUID      `db:"host_id" json:"host_id"`
	HostDeviceID    string         `db:"host_device_id" json:"host_device_id"`
	SessionToken    string         `db:"session_token" json:"session_token"`
	SessionType     string         `db:"session_type" json:"session_type"`
	Quality         string         `db:"quality" json:"quality"`
	EncryptionType  string         `db:"encryption_type" json:"encryption_type"`
	StartedAt       sql.NullTime   `db:"started_at" json:"started_at"`
	EndedAt         sql.NullTime   `db:"ended_at" json:"ended_at"`
	DurationSeconds sql.NullInt32  `db:"duration_seconds" json:"duration_seconds"`
	EndReason       sql.NullString `db:"end_reason" json:"end_reason"`
	BytesSent       int64          `db:"bytes_sent" json:"bytes_sent"`
	BytesReceived   int64          `db:"bytes_received" json:"bytes_received"`
	AvgLatencyMs    sql.NullInt32  `db:"avg_latency_ms" json:"avg_latency_ms"`
	Recorded        bool           `db:"recorded" json:"recorded"`
	RecordingURL    sql.NullString `db:"recording_url" json:"recording_url"`
	CreatedAt       time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt       time.Time      `db:"updated_at" json:"updated_at"`
}

type SessionPermission struct {
	ID                uuid.UUID `db:"id" json:"id"`
	SessionID         uuid.UUID `db:"session_id" json:"session_id"`
	AllowKeyboard     bool      `db:"allow_keyboard" json:"allow_keyboard"`
	AllowMouse        bool      `db:"allow_mouse" json:"allow_mouse"`
	AllowClipboard    bool      `db:"allow_clipboard" json:"allow_clipboard"`
	AllowFileTransfer bool      `db:"allow_file_transfer" json:"allow_file_transfer"`
	AllowAudio        bool      `db:"allow_audio" json:"allow_audio"`
	AllowRestart      bool      `db:"allow_restart" json:"allow_restart"`
	AllowLockScreen   bool      `db:"allow_lock_screen" json:"allow_lock_screen"`
	UpdatedAt         time.Time `db:"updated_at" json:"updated_at"`
	CreatedAt         time.Time `db:"created_at" json:"created_at"`
}

type UnattendedAccess struct {
	ID                 uuid.UUID `db:"id" json:"id"`
	HostUserID         uuid.UUID `db:"host_user_id" json:"host_user_id"`
	ControllerUserID   uuid.UUID `db:"controller_user_id" json:"controller_user_id"`
	AccessPasswordHash string    `db:"access_password_hash" json:"-"`
	IsActive           bool      `db:"is_active" json:"is_active"`
	CreatedAt          time.Time `db:"created_at" json:"created_at"`
	UpdatedAt          time.Time `db:"updated_at" json:"updated_at"`
}

type CommunityAnnouncement struct {
	ID          uuid.UUID `db:"id" json:"id"`
	CommunityID uuid.UUID `db:"community_id" json:"community_id"`
	AuthorID    uuid.UUID `db:"author_id" json:"author_id"`
	Title       string    `db:"title" json:"title"`
	Content     string    `db:"content" json:"content"`
	IsPinned    bool      `db:"is_pinned" json:"is_pinned"`
	CreatedAt   time.Time `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time `db:"updated_at" json:"updated_at"`
}

type CommunityInvite struct {
	ID          uuid.UUID     `db:"id" json:"id"`
	CommunityID uuid.UUID     `db:"community_id" json:"community_id"`
	CreatedBy   uuid.UUID     `db:"created_by" json:"created_by"`
	Code        string        `db:"code" json:"code"`
	MaxUses     sql.NullInt32 `db:"max_uses" json:"max_uses"`
	UsesCount   int           `db:"uses_count" json:"uses_count"`
	ExpiresAt   sql.NullTime  `db:"expires_at" json:"expires_at"`
	IsActive    bool          `db:"is_active" json:"is_active"`
	CreatedAt   time.Time     `db:"created_at" json:"created_at"`
}

type CommunityBan struct {
	ID          uuid.UUID      `db:"id" json:"id"`
	CommunityID uuid.UUID      `db:"community_id" json:"community_id"`
	UserID      uuid.UUID      `db:"user_id" json:"user_id"`
	BannedBy    uuid.UUID      `db:"banned_by" json:"banned_by"`
	Reason      sql.NullString `db:"reason" json:"reason"`
	ExpiresAt   sql.NullTime   `db:"expires_at" json:"expires_at"`
	CreatedAt   time.Time      `db:"created_at" json:"created_at"`
}

type CommunityAuditLog struct {
	ID           uuid.UUID     `db:"id" json:"id"`
	CommunityID  uuid.UUID     `db:"community_id" json:"community_id"`
	ActorID      uuid.UUID     `db:"actor_id" json:"actor_id"`
	Action       string        `db:"action" json:"action"`
	TargetUserID uuid.NullUUID `db:"target_user_id" json:"target_user_id"`
	Metadata     []byte        `db:"metadata" json:"metadata"`
	CreatedAt    time.Time     `db:"created_at" json:"created_at"`
}

type MessageReaction struct {
	ID          uuid.UUID `db:"id" json:"id"`
	MessageID   uuid.UUID `db:"message_id" json:"message_id"`
	MessageType string    `db:"message_type" json:"message_type"`
	UserID      uuid.UUID `db:"user_id" json:"user_id"`
	Emoji       string    `db:"emoji" json:"emoji"`
	CreatedAt   time.Time `db:"created_at" json:"created_at"`
}

type MessageAttachment struct {
	ID            uuid.UUID      `db:"id" json:"id"`
	MessageID     uuid.UUID      `db:"message_id" json:"message_id"`
	MessageType   string         `db:"message_type" json:"message_type"`
	UploaderID    uuid.UUID      `db:"uploader_id" json:"uploader_id"`
	FileName      string         `db:"file_name" json:"file_name"`
	FileSizeBytes sql.NullInt64  `db:"file_size_bytes" json:"file_size_bytes"`
	MimeType      sql.NullString `db:"mime_type" json:"mime_type"`
	StorageURL    string         `db:"storage_url" json:"storage_url"`
	ThumbnailURL  sql.NullString `db:"thumbnail_url" json:"thumbnail_url"`
	CreatedAt     time.Time      `db:"created_at" json:"created_at"`
}

type Plan struct {
	ID                    uuid.UUID      `db:"id" json:"id"`
	Name                  string         `db:"name" json:"name"`
	DisplayName           sql.NullString `db:"display_name" json:"display_name"`
	MaxConcurrentSessions sql.NullInt32  `db:"max_concurrent_sessions" json:"max_concurrent_sessions"`
	MaxCommunityMembers   sql.NullInt32  `db:"max_community_members" json:"max_community_members"`
	MaxCommunities        sql.NullInt32  `db:"max_communities" json:"max_communities"`
	UnattendedAccess      bool           `db:"unattended_access" json:"unattended_access"`
	SessionRecording      bool           `db:"session_recording" json:"session_recording"`
	PrioritySupport       bool           `db:"priority_support" json:"priority_support"`
	CustomAlias           bool           `db:"custom_alias" json:"custom_alias"`
	PriceMonthlyUSD       sql.NullString `db:"price_monthly_usd" json:"price_monthly_usd"`
	PriceYearlyUSD        sql.NullString `db:"price_yearly_usd" json:"price_yearly_usd"`
	CreatedAt             time.Time      `db:"created_at" json:"created_at"`
}

type UserSubscription struct {
	ID                     uuid.UUID      `db:"id" json:"id"`
	UserID                 uuid.UUID      `db:"user_id" json:"user_id"`
	PlanID                 uuid.UUID      `db:"plan_id" json:"plan_id"`
	Status                 string         `db:"status" json:"status"`
	BillingCycle           sql.NullString `db:"billing_cycle" json:"billing_cycle"`
	CurrentPeriodStart     sql.NullTime   `db:"current_period_start" json:"current_period_start"`
	CurrentPeriodEnd       sql.NullTime   `db:"current_period_end" json:"current_period_end"`
	TrialEnd               sql.NullTime   `db:"trial_end" json:"trial_end"`
	CancelledAt            sql.NullTime   `db:"cancelled_at" json:"cancelled_at"`
	ExternalSubscriptionID sql.NullString `db:"external_subscription_id" json:"external_subscription_id"`
	CreatedAt              time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt              time.Time      `db:"updated_at" json:"updated_at"`
}

type PushToken struct {
	ID                uuid.UUID      `db:"id" json:"id"`
	UserID            uuid.UUID      `db:"user_id" json:"user_id"`
	Token             string         `db:"token" json:"token"`
	Platform          string         `db:"platform" json:"platform"`
	DeviceFingerprint sql.NullString `db:"device_fingerprint" json:"device_fingerprint"`
	IsActive          bool           `db:"is_active" json:"is_active"`
	CreatedAt         time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt         time.Time      `db:"updated_at" json:"updated_at"`
}

type DataExportRequest struct {
	ID          uuid.UUID      `db:"id" json:"id"`
	UserID      uuid.UUID      `db:"user_id" json:"user_id"`
	Status      string         `db:"status" json:"status"`
	DownloadURL sql.NullString `db:"download_url" json:"download_url"`
	ReadyAt     sql.NullTime   `db:"ready_at" json:"ready_at"`
	CreatedAt   time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt   time.Time      `db:"updated_at" json:"updated_at"`
}

type AccountDeletionRequest struct {
	ID           uuid.UUID      `db:"id" json:"id"`
	UserID       uuid.UUID      `db:"user_id" json:"user_id"`
	RequestedBy  uuid.UUID      `db:"requested_by" json:"requested_by"`
	Reason       sql.NullString `db:"reason" json:"reason"`
	Status       string         `db:"status" json:"status"`
	ScheduledFor time.Time      `db:"scheduled_for" json:"scheduled_for"`
	ProcessedAt  sql.NullTime   `db:"processed_at" json:"processed_at"`
	CreatedAt    time.Time      `db:"created_at" json:"created_at"`
	UpdatedAt    time.Time      `db:"updated_at" json:"updated_at"`
}
