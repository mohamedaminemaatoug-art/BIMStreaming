package websocket

import (
	"context"
	"encoding/json"
	"sync"

	"bimstreaming/signaling-go/internal/service"
	"bimstreaming/signaling-go/pkg/metrics"
	"github.com/gorilla/websocket"
)

type Hub struct {
	mu       sync.RWMutex
	clients  map[string]*websocket.Conn
	presence service.PresenceService
}

func NewHub(presence service.PresenceService) *Hub {
	return &Hub{clients: map[string]*websocket.Conn{}, presence: presence}
}

func (h *Hub) Register(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.clients[userID] = conn
	metrics.WSConnections.Set(float64(len(h.clients)))
}

func (h *Hub) Unregister(userID string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	delete(h.clients, userID)
	metrics.WSConnections.Set(float64(len(h.clients)))
}

func (h *Hub) Route(ctx context.Context, msg Message) error {
	b, err := json.Marshal(msg)
	if err != nil {
		return err
	}

	if err := h.presence.Publish(ctx, "signal.route", string(b)); err != nil {
		return err
	}
	return h.SendTo(msg.To, b)
}

func (h *Hub) SendTo(to string, raw []byte) error {
	h.mu.RLock()
	conn, ok := h.clients[to]
	h.mu.RUnlock()
	if !ok || conn == nil {
		return nil
	}
	return conn.WriteMessage(websocket.TextMessage, raw)
}

func (h *Hub) StartRedisSubscriber(ctx context.Context, rdbSub service.PresenceService) {
	_ = ctx
	_ = rdbSub
	// In production, use dedicated redis pubsub subscription here for multi-instance routing.
}
