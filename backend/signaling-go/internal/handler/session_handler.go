package handler

import (
	"context"
	"encoding/json"
	"net/http"

	"bimstreaming/signaling-go/internal/service"
)

type SessionHandler struct {
	session service.SessionService
}

func NewSessionHandler(session service.SessionService) *SessionHandler {
	return &SessionHandler{session: session}
}

type createSessionRequest struct {
	DeviceFrom string `json:"device_from"`
	DeviceTo   string `json:"device_to"`
}

type updateSessionRequest struct {
	SessionID string `json:"session_id"`
}

func (h *SessionHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req createSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}
	s, err := h.session.CreatePending(r.Context(), req.DeviceFrom, req.DeviceTo)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(s)
}

func (h *SessionHandler) Accept(w http.ResponseWriter, r *http.Request) {
	h.updateStatus(w, r, h.session.Accept)
}

func (h *SessionHandler) Reject(w http.ResponseWriter, r *http.Request) {
	h.updateStatus(w, r, h.session.Reject)
}

func (h *SessionHandler) End(w http.ResponseWriter, r *http.Request) {
	h.updateStatus(w, r, h.session.End)
}

func (h *SessionHandler) updateStatus(w http.ResponseWriter, r *http.Request, fn func(ctx context.Context, sessionID string) error) {
	var req updateSessionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}
	if err := fn(r.Context(), req.SessionID); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
