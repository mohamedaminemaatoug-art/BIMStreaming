package push

import (
	"context"
	"encoding/json"
	"log"
	"strings"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

type PushTokenProvider interface {
	ListActivePushTokens(ctx context.Context, userID uuid.UUID) ([]models.PushToken, error)
}

type DispatchJob struct {
	UserID       uuid.UUID
	Notification *models.Notification
}

type Dispatcher struct {
	repo   PushTokenProvider
	sender *FCMSender
	jobs   chan DispatchJob
}

func NewDispatcher(repo PushTokenProvider, sender *FCMSender, buffer int) *Dispatcher {
	if buffer <= 0 {
		buffer = 64
	}
	return &Dispatcher{repo: repo, sender: sender, jobs: make(chan DispatchJob, buffer)}
}

func (d *Dispatcher) Start(ctx context.Context) {
	if d == nil {
		return
	}
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case job := <-d.jobs:
				d.dispatchOne(ctx, job)
			}
		}
	}()
}

func (d *Dispatcher) Enqueue(userID uuid.UUID, notification *models.Notification) {
	if d == nil || notification == nil {
		return
	}
	select {
	case d.jobs <- DispatchJob{UserID: userID, Notification: notification}:
	default:
		log.Printf("push dispatcher queue full; dropping notification %s", notification.ID)
	}
}

func (d *Dispatcher) dispatchOne(ctx context.Context, job DispatchJob) {
	if d == nil || d.sender == nil || !d.sender.Enabled() || d.repo == nil || job.Notification == nil {
		return
	}
	tokens, err := d.repo.ListActivePushTokens(ctx, job.UserID)
	if err != nil {
		log.Printf("push dispatch list tokens failed: %v", err)
		return
	}
	fcmTokens := make([]string, 0, len(tokens))
	for _, token := range tokens {
		if token.Platform == "fcm" && token.IsActive {
			fcmTokens = append(fcmTokens, token.Token)
		}
	}
	if len(fcmTokens) == 0 {
		return
	}
	title, body := renderPushMessage(job.Notification.Type)
	data := map[string]string{
		"notification_id": job.Notification.ID.String(),
		"type":            job.Notification.Type,
	}
	if len(job.Notification.Payload) > 0 {
		data["payload"] = string(job.Notification.Payload)
	}
	if err := d.sender.SendToTokens(ctx, fcmTokens, title, body, data); err != nil {
		log.Printf("push dispatch send failed: %v", err)
	}
}

func renderPushMessage(notificationType string) (string, string) {
	kind := strings.TrimSpace(strings.ToLower(notificationType))
	switch kind {
	case "dm":
		return "New direct message", "You received a new message."
	case "friend_request":
		return "New friend request", "Someone sent you a friend request."
	case "remote_session_request":
		return "Remote session request", "You received a remote session request."
	default:
		return "New notification", "You have a new notification."
	}
}

func PayloadToMap(payload any) map[string]string {
	raw, err := json.Marshal(payload)
	if err != nil {
		return map[string]string{}
	}
	return map[string]string{"payload": string(raw)}
}
