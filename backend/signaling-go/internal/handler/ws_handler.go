package handler

import (
	"encoding/json"
	"log"
	"net/http"

	appws "bimstreaming/signaling-go/internal/websocket"
	gws "github.com/gorilla/websocket"
)

type WSHandler struct {
	hub      *appws.Hub
	upgrader gws.Upgrader
}

func NewWSHandler(hub *appws.Hub, readBuffer, writeBuffer int) *WSHandler {
	return &WSHandler{
		hub: hub,
		upgrader: gws.Upgrader{
			ReadBufferSize:  readBuffer,
			WriteBufferSize: writeBuffer,
			CheckOrigin: func(r *http.Request) bool {
				return true
			},
		},
	}
}

func (h *WSHandler) ServeWS(w http.ResponseWriter, r *http.Request) {
	userID := r.URL.Query().Get("user_id")
	if userID == "" {
		userID = r.URL.Query().Get("userId")
	}
	if userID == "" {
		http.Error(w, "missing user_id", http.StatusBadRequest)
		return
	}

	conn, err := h.upgrader.Upgrade(w, r, nil)
	if err != nil {
		http.Error(w, "upgrade failed", http.StatusBadRequest)
		return
	}

	h.hub.Register(userID, conn)
	log.Printf("WS connected user=%s", userID)
	defer func() {
		h.hub.Unregister(userID, conn)
		log.Printf("WS disconnected user=%s", userID)
		_ = conn.Close()
	}()

	for {
		_, data, err := conn.ReadMessage()
		if err != nil {
			return
		}

		// Compatibility path for Flutter signaling envelope:
		// {"type":"session_message","data":{"toUserId":"...", ...}}
		var raw map[string]interface{}
		if err := json.Unmarshal(data, &raw); err == nil {
			if msgType, ok := raw["type"].(string); ok {
				log.Printf("WS incoming type=%s from=%s", msgType, userID)
			}
			if msgType, ok := raw["type"].(string); ok && msgType == "session_message" {
				var dataObj map[string]interface{}
				switch d := raw["data"].(type) {
				case map[string]interface{}:
					dataObj = d
				default:
					if b, err := json.Marshal(d); err == nil {
						_ = json.Unmarshal(b, &dataObj)
					}
				}

				if dataObj == nil {
					log.Printf("WS session_message dropped: invalid data payload from=%s", userID)
					continue
				}

				if _, exists := dataObj["fromUserId"]; !exists {
					dataObj["fromUserId"] = userID
				}

				toUserID, _ := dataObj["toUserId"].(string)
				if toUserID == "" {
					if altTo, ok := raw["to"].(string); ok {
						toUserID = altTo
					}
				}

				if toUserID == "" {
					log.Printf("WS session_message dropped: missing toUserId from=%s", userID)
					continue
				}

				forward := map[string]interface{}{
					"type": "session_message",
					"data": dataObj,
				}
				if forwardBytes, err := json.Marshal(forward); err == nil {
					log.Printf("WS session_message route from=%s to=%s sessionId=%v", userID, toUserID, dataObj["sessionId"])
					_ = h.hub.SendTo(toUserID, forwardBytes)
					continue
				}
			}
		}

		var msg appws.Message
		if err := json.Unmarshal(data, &msg); err != nil {
			continue
		}
		_ = h.hub.Route(r.Context(), msg)
	}
}
