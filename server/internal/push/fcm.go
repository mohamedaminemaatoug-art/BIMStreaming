package push

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

type FCMSender struct {
	serverKey string
	endpoint  string
	client    *http.Client
}

type fcmNotification struct {
	Title string `json:"title"`
	Body  string `json:"body"`
}

type fcmPayload struct {
	RegistrationIDs []string          `json:"registration_ids"`
	Priority        string            `json:"priority,omitempty"`
	Notification    fcmNotification   `json:"notification"`
	Data            map[string]string `json:"data,omitempty"`
}

func NewFCMSender(serverKey, endpoint string) *FCMSender {
	return &FCMSender{
		serverKey: strings.TrimSpace(serverKey),
		endpoint:  strings.TrimSpace(endpoint),
		client:    &http.Client{Timeout: 8 * time.Second},
	}
}

func (s *FCMSender) Enabled() bool {
	return s != nil && s.serverKey != "" && s.endpoint != ""
}

func (s *FCMSender) SendToTokens(ctx context.Context, tokens []string, title, body string, data map[string]string) error {
	if s == nil || !s.Enabled() || len(tokens) == 0 {
		return nil
	}
	payload := fcmPayload{
		RegistrationIDs: tokens,
		Priority:        "high",
		Notification: fcmNotification{
			Title: title,
			Body:  body,
		},
		Data: data,
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.endpoint, bytes.NewReader(raw))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "key="+s.serverKey)
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("fcm send failed: status %d", resp.StatusCode)
	}
	return nil
}
