package ws

import (
	"encoding/json"
	"log"
	"sync"

	"github.com/gorilla/websocket"
)

type Event struct {
	Type    string      `json:"type"`
	Payload interface{} `json:"payload"`
}

type Hub struct {
	mu          sync.RWMutex
	connections map[string]map[*websocket.Conn]struct{}
}

func NewHub() *Hub {
	return &Hub{connections: make(map[string]map[*websocket.Conn]struct{})}
}

func (h *Hub) Register(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if _, ok := h.connections[userID]; !ok {
		h.connections[userID] = make(map[*websocket.Conn]struct{})
	}
	h.connections[userID][conn] = struct{}{}
}

func (h *Hub) Unregister(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	conns, ok := h.connections[userID]
	if !ok {
		return
	}
	delete(conns, conn)
	if len(conns) == 0 {
		delete(h.connections, userID)
	}
}

func (h *Hub) PublishToUser(userID string, eventType string, payload interface{}) {
	event := Event{Type: eventType, Payload: payload}
	raw, err := json.Marshal(event)
	if err != nil {
		log.Printf("ws publish marshal error: %v", err)
		return
	}
	h.mu.RLock()
	conns, ok := h.connections[userID]
	if !ok {
		h.mu.RUnlock()
		return
	}
	copyConns := make([]*websocket.Conn, 0, len(conns))
	for c := range conns {
		copyConns = append(copyConns, c)
	}
	h.mu.RUnlock()

	for _, conn := range copyConns {
		if err := conn.WriteMessage(websocket.TextMessage, raw); err != nil {
			log.Printf("ws write error for user %s: %v", userID, err)
		}
	}
}

func (h *Hub) PublishToMany(userIDs []string, eventType string, payload interface{}) {
	for _, uid := range userIDs {
		h.PublishToUser(uid, eventType, payload)
	}
}

func (h *Hub) HasConnections(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	conns, ok := h.connections[userID]
	return ok && len(conns) > 0
}
