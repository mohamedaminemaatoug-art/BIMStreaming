package handlers

import (
	"net/http"
	"strings"
)

type registerPushTokenRequest struct {
	Token             string `json:"token"`
	Platform          string `json:"platform"`
	DeviceFingerprint string `json:"device_fingerprint"`
}

type unregisterPushTokenRequest struct {
	Token             string `json:"token"`
	DeviceFingerprint string `json:"device_fingerprint"`
}

func (a *App) RegisterPushToken(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body registerPushTokenRequest
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	platform := strings.ToLower(strings.TrimSpace(body.Platform))
	if strings.TrimSpace(body.Token) == "" || (platform != "fcm" && platform != "apns" && platform != "web") {
		badRequest(w, "invalid token registration")
		return
	}
	token, err := a.Repo.RegisterPushToken(r.Context(), userID, body.Token, platform, body.DeviceFingerprint)
	if err != nil {
		internalError(w, "failed to register push token")
		return
	}
	writeJSON(w, http.StatusCreated, token)
}

func (a *App) UnregisterPushToken(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body unregisterPushTokenRequest
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	if strings.TrimSpace(body.Token) == "" && strings.TrimSpace(body.DeviceFingerprint) == "" {
		badRequest(w, "token or device_fingerprint required")
		return
	}
	if err := a.Repo.UnregisterPushToken(r.Context(), userID, body.Token, body.DeviceFingerprint); err != nil {
		internalError(w, "failed to unregister push token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "push token unregistered"})
}
