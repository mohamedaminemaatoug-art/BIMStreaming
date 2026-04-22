package handlers

import (
	"database/sql"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/go-chi/chi/v5"
)

func isMissingStatusTableError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, `relation "user_status" does not exist`) ||
		strings.Contains(msg, "relation user_status does not exist")
}

func (a *App) GetMe(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	ds, _ := a.Repo.GetDeviceSessionByUserID(r.Context(), userID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"user": map[string]interface{}{
			"id":                 user.ID,
			"username":           user.Username,
			"email":              user.Email,
			"device_id":          user.DeviceID,
			"avatar_url":         strings.TrimSpace(user.AvatarURL.String),
			"display_name":       strings.TrimSpace(user.DisplayName.String),
			"bio":                strings.TrimSpace(user.Bio.String),
			"is_online":          user.IsOnline,
			"two_factor_enabled": user.TwoFactorEnabled,
		},
		"device_session": ds,
	})
}

func (a *App) UpdateMe(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		Username    string `json:"username"`
		DisplayName string `json:"display_name"`
		Phone       string `json:"phone"`
		Bio         string `json:"bio"`
		Theme       string `json:"theme"`
		Language    string `json:"language"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	user, err := a.Repo.UpdateUserProfile(
		r.Context(),
		userID,
		body.Username,
		body.DisplayName,
		body.Phone,
		body.Bio,
		body.Theme,
		body.Language,
	)
	if err != nil {
		internalError(w, "failed to update user")
		return
	}
	writeJSON(w, http.StatusOK, user)
}

func (a *App) UpdateMyNotifications(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body map[string]interface{}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		badRequest(w, "invalid notification preferences")
		return
	}
	if err := a.Repo.UpdateNotificationPreferences(r.Context(), userID, encoded); err != nil {
		internalError(w, "failed to update notification preferences")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "notification preferences updated"})
}

func (a *App) GetMySubscription(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}

	sub, err := a.Repo.GetUserSubscription(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to load subscription")
		return
	}
	if sub == nil {
		plan, planErr := a.Repo.GetPlanByName(r.Context(), "free")
		if planErr != nil {
			internalError(w, "failed to load default plan")
			return
		}
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"subscription": map[string]interface{}{
				"status":    "inactive",
				"plan_name": plan.Name,
				"plan_id":   plan.ID,
			},
		})
		return
	}

	plan, err := a.Repo.GetPlanByID(r.Context(), sub.PlanID)
	if err != nil {
		internalError(w, "failed to load plan")
		return
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"subscription": map[string]interface{}{
			"id":                   sub.ID,
			"status":               sub.Status,
			"plan_id":              sub.PlanID,
			"plan_name":            plan.Name,
			"billing_cycle":        sub.BillingCycle,
			"current_period_start": sub.CurrentPeriodStart,
			"current_period_end":   sub.CurrentPeriodEnd,
		},
	})
}

func (a *App) GetMyStatus(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	status, err := a.Repo.GetUserStatus(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]interface{}{"status": nil})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"status": status})
}

func (a *App) UpdateMyStatus(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		Emoji        string `json:"emoji"`
		Message      string `json:"message"`
		Availability string `json:"availability"`
		ExpiresAt    string `json:"expires_at"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	availability := strings.ToLower(strings.TrimSpace(body.Availability))
	if availability == "" {
		availability = "online"
	}
	if availability != "online" && availability != "away" && availability != "busy" && availability != "offline" {
		badRequest(w, "invalid availability")
		return
	}
	status := models.UserStatus{UserID: userID, Availability: availability, Emoji: nullString(body.Emoji), Message: nullString(body.Message)}
	if strings.TrimSpace(body.ExpiresAt) != "" {
		parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(body.ExpiresAt))
		if err != nil {
			badRequest(w, "invalid expires_at")
			return
		}
		status.ExpiresAt = sql.NullTime{Time: parsed, Valid: true}
	}
	saved, err := a.Repo.UpsertUserStatus(r.Context(), status)
	if err != nil {
		internalError(w, "failed to update status")
		return
	}
	if a.Hub != nil {
		a.Hub.PublishToUser(userID.String(), "status.updated", saved)
	}
	writeJSON(w, http.StatusOK, saved)
}

func (a *App) UploadAvatar(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	if err := r.ParseMultipartForm(a.Avatar.MaxUploadSize()); err != nil {
		badRequest(w, "invalid multipart upload")
		return
	}
	file, header, err := r.FormFile("avatar")
	if err != nil {
		badRequest(w, "avatar file required")
		return
	}
	defer file.Close()
	avatarURL, err := a.Avatar.SaveUploadedAvatar(file, header, userID)
	if err != nil {
		badRequest(w, err.Error())
		return
	}
	if err := a.Repo.UpdateUserAvatar(r.Context(), userID, avatarURL); err != nil {
		internalError(w, "failed to update avatar")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"avatar_url": avatarURL})
}

func (a *App) GetUserProfile(w http.ResponseWriter, r *http.Request) {
	viewerID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	targetID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), targetID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	status, _ := a.Repo.GetUserStatus(r.Context(), targetID)
	mutual, _ := a.Repo.GetMutualFriendCount(r.Context(), viewerID, targetID)
	displayName := strings.TrimSpace(user.DisplayName.String)
	if displayName == "" {
		displayName = user.Username
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"id":             user.ID,
		"username":       user.Username,
		"display_name":   displayName,
		"avatar_url":     strings.TrimSpace(user.AvatarURL.String),
		"is_online":      user.IsOnline,
		"status":         status,
		"mutual_friends": mutual,
	})
}

func (a *App) GetUserStatus(w http.ResponseWriter, r *http.Request) {
	_, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	targetID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	status, err := a.Repo.GetUserStatus(r.Context(), targetID)
	if err != nil {
		if isMissingStatusTableError(err) {
			writeJSON(w, http.StatusOK, map[string]interface{}{"status": nil})
			return
		}
		internalError(w, "failed to load status")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"status": status})
}

func (a *App) SearchUsers(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")
	cursor := r.URL.Query().Get("cursor")
	limit := intQueryDefault(r, "limit", 50)
	users, next, hasMore, err := a.Repo.SearchUsers(r.Context(), q, cursor, limit)
	if err != nil {
		badRequest(w, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: users, NextCursor: next, HasMore: hasMore})
}

func (a *App) ServeAvatar(w http.ResponseWriter, r *http.Request) {
	filename := filepath.Base(chi.URLParam(r, "filename"))
	if filename == "" {
		notFound(w, "avatar not found")
		return
	}
	path := a.Avatar.AvatarFilePath(filename)
	if _, err := os.Stat(path); err != nil {
		notFound(w, "avatar not found")
		return
	}
	http.ServeFile(w, r, path)
}
