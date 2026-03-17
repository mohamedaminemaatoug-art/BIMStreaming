package handler

import (
	"encoding/json"
	"net/http"

	"bimstreaming/signaling-go/internal/service"
)

type ICEHandler struct {
	ice service.ICEService
}

func NewICEHandler(ice service.ICEService) *ICEHandler {
	return &ICEHandler{ice: ice}
}

func (h *ICEHandler) GetICEServers(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]interface{}{
		"ice_servers": h.ice.BuildICEServers(),
	})
}
