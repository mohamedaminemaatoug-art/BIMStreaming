package handler

import (
	"encoding/json"
	"net/http"
	"time"

	"bimstreaming/signaling-go/internal/models"
	"bimstreaming/signaling-go/internal/service"
	"github.com/google/uuid"
)

type DeviceHandler struct {
	device service.DeviceService
}

func NewDeviceHandler(device service.DeviceService) *DeviceHandler {
	return &DeviceHandler{device: device}
}

func (h *DeviceHandler) Register(w http.ResponseWriter, r *http.Request) {
	var d models.Device
	if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
		http.Error(w, "invalid payload", http.StatusBadRequest)
		return
	}
	if d.ID == "" {
		d.ID = uuid.NewString()
	}
	d.LastSeenAt = time.Now().UTC()
	if err := h.device.Register(r.Context(), &d); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(d)
}
