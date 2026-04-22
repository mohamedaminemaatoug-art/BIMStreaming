package email

import (
	"bytes"
	"fmt"
	"html/template"
	"log"
	"net/smtp"
	"os"
	"path/filepath"
	"strings"
)

var templateValidationData = map[string]map[string]interface{}{
	"verify_email":      {"code": "123456", "expires": "10 minutes"},
	"reset_password":    {"code": "123456", "expires": "10 minutes"},
	"welcome":           {},
	"login_alert":       {"country": "US", "city": "Seattle", "when": "2026-01-01T00:00:00Z", "device_info": "Windows 11"},
	"account_locked":    {"lock_minutes": 15},
	"community_invite":  {"community_name": "Support Team", "invite_url": "https://example.invalid/invite"},
	"friend_request":    {"requester_name": "alex", "profile_url": "https://example.invalid/u/alex"},
	"subscription_conf": {"plan_name": "pro"},
	"data_export_ready": {"export_url": "https://example.invalid/export.zip"},
	"account_deletion":  {"deletion_date": "2026-02-01"},
}

type Sender struct {
	host        string
	port        int
	user        string
	pass        string
	from        string
	templateDir string
}

func NewSender(host string, port int, user, pass, from string) *Sender {
	return &Sender{
		host:        strings.TrimSpace(host),
		port:        port,
		user:        strings.TrimSpace(user),
		pass:        strings.ReplaceAll(strings.TrimSpace(pass), " ", ""),
		from:        strings.TrimSpace(from),
		templateDir: filepath.Join("internal", "email", "templates"),
	}
}

func (s *Sender) SendVerificationCode(toEmail, code string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Verify your email", "verify_email", map[string]interface{}{
		"code":    code,
		"expires": "10 minutes",
	})
}

func (s *Sender) SendPasswordReset(toEmail, code string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Password reset code", "reset_password", map[string]interface{}{
		"code":    code,
		"expires": "10 minutes",
	})
}

func (s *Sender) SendCommunityInvite(toEmail, inviteURL, communityName string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Community invite", "community_invite", map[string]interface{}{
		"community_name": communityName,
		"invite_url":     inviteURL,
	})
}

func (s *Sender) SendWelcome(toEmail string) error {
	return s.sendTemplate(toEmail, "Welcome to BimStreaming", "welcome", map[string]interface{}{})
}

func (s *Sender) SendLoginAlert(toEmail, country, city, when, deviceInfo string) error {
	return s.sendTemplate(toEmail, "BimStreaming - New login detected", "login_alert", map[string]interface{}{
		"country":     country,
		"city":        city,
		"when":        when,
		"device_info": deviceInfo,
	})
}

func (s *Sender) SendAccountLocked(toEmail string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Account locked", "account_locked", map[string]interface{}{
		"lock_minutes": 15,
	})
}

func (s *Sender) SendFriendRequest(toEmail, requesterName, profileURL string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Friend request", "friend_request", map[string]interface{}{
		"requester_name": requesterName,
		"profile_url":    profileURL,
	})
}

func (s *Sender) SendSubscriptionConfirmation(toEmail, planName string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Subscription confirmed", "subscription_conf", map[string]interface{}{
		"plan_name": planName,
	})
}

func (s *Sender) SendDataExportReady(toEmail, exportURL string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Data export ready", "data_export_ready", map[string]interface{}{
		"export_url": exportURL,
	})
}

func (s *Sender) SendAccountDeletionNotice(toEmail, deletionDate string) error {
	return s.sendTemplate(toEmail, "BimStreaming - Account deletion scheduled", "account_deletion", map[string]interface{}{
		"deletion_date": deletionDate,
	})
}

func (s *Sender) sendTemplate(toEmail, subject, templateName string, data map[string]interface{}) error {
	body, err := s.renderTemplate(templateName, data)
	if err != nil {
		return err
	}
	if err := s.sendHTML(toEmail, subject, body); err != nil {
		return err
	}
	log.Printf("Email sent: type=%s to=%s", templateName, toEmail)
	return nil
}

func (s *Sender) renderTemplate(templateName string, data map[string]interface{}) (string, error) {
	path := filepath.Join(s.templateDir, templateName+".html")
	raw, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	tpl, err := template.New(templateName).Parse(string(raw))
	if err != nil {
		return "", err
	}
	var rendered bytes.Buffer
	if err := tpl.Execute(&rendered, data); err != nil {
		return "", err
	}
	return rendered.String(), nil
}

func (s *Sender) sendHTML(toEmail, subject, body string) error {
	if s.host == "" || s.from == "" {
		return fmt.Errorf("smtp host/from are required")
	}
	if strings.Contains(strings.ToLower(s.host), "gmail") && (s.user == "" || s.pass == "") {
		return fmt.Errorf("gmail smtp requires SMTP_USER and SMTP_PASS")
	}
	envelopeFrom := s.from
	fromHeader := s.from
	if strings.Contains(strings.ToLower(s.host), "gmail") && s.user != "" {
		envelopeFrom = s.user
		fromHeader = s.user
	}
	addr := fmt.Sprintf("%s:%d", s.host, s.port)
	headers := []string{
		"From: " + fromHeader,
		"To: " + toEmail,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/html; charset=UTF-8",
	}
	msg := strings.Join(headers, "\r\n") + "\r\n\r\n" + body
	var auth smtp.Auth
	if s.user != "" {
		auth = smtp.PlainAuth("", s.user, s.pass, s.host)
	}
	return smtp.SendMail(addr, auth, envelopeFrom, []string{toEmail}, []byte(msg))
}

func (s *Sender) VerifyTemplates() error {
	for templateName, data := range templateValidationData {
		if _, err := s.renderTemplate(templateName, data); err != nil {
			return fmt.Errorf("template %s failed to render: %w", templateName, err)
		}
	}
	return nil
}
