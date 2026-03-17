package handler

import (
	"encoding/json"
	"net/http"

	"bimstreaming/signaling-go/internal/service"
	appws "bimstreaming/signaling-go/internal/websocket"
)

type SignalingCompatHandler struct {
	sessionSvc service.SessionService
	hub        *appws.Hub
}

func NewSignalingCompatHandler(sessionSvc service.SessionService, hub *appws.Hub) *SignalingCompatHandler {
	return &SignalingCompatHandler{sessionSvc: sessionSvc, hub: hub}
}

type requestSessionCompatPayload struct {
	FromUserID string `json:"fromUserId"`
	FromName   string `json:"fromName"`
	ToUserID   string `json:"toUserId"`
}

type respondSessionCompatPayload struct {
	SessionID  string `json:"sessionId"`
	FromUserID string `json:"fromUserId"`
	ToUserID   string `json:"toUserId"`
	Accepted   bool   `json:"accepted"`
}

func (h *SignalingCompatHandler) Request(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req requestSessionCompatPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}
	if req.FromUserID == "" || req.ToUserID == "" {
		http.Error(w, "missing user ids", http.StatusBadRequest)
		return
	}

	s, err := h.sessionSvc.CreatePending(r.Context(), req.FromUserID, req.ToUserID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	incoming := map[string]interface{}{
		"type": "incoming_request",
		"data": map[string]interface{}{
			"sessionId":  s.ID,
			"fromUserId": req.FromUserID,
			"fromName":   req.FromName,
		},
	}
	if raw, err := json.Marshal(incoming); err == nil {
		_ = h.hub.SendTo(req.ToUserID, raw)
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success":   true,
		"sessionId": s.ID,
		"message":   "request sent",
	})
}

func (h *SignalingCompatHandler) Respond(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req respondSessionCompatPayload
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}
	if req.SessionID == "" || req.FromUserID == "" || req.ToUserID == "" {
		http.Error(w, "missing required fields", http.StatusBadRequest)
		return
	}

	if req.Accepted {
		if err := h.sessionSvc.Accept(r.Context(), req.SessionID); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	} else {
		if err := h.sessionSvc.Reject(r.Context(), req.SessionID); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
	}

	response := map[string]interface{}{
		"type": "session_response",
		"data": map[string]interface{}{
			"sessionId":  req.SessionID,
			"accepted":   req.Accepted,
			"fromUserId": req.FromUserID,
			"fromName":   req.FromUserID,
		},
	}
	if raw, err := json.Marshal(response); err == nil {
		_ = h.hub.SendTo(req.ToUserID, raw)
	}

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"success": true,
		"status":  map[bool]string{true: "accepted", false: "rejected"}[req.Accepted],
	})
}
