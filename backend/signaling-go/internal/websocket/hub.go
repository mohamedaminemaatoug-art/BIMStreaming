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
	clients  map[string]map[*websocket.Conn]struct{}
	presence service.PresenceService
}

func NewHub(presence service.PresenceService) *Hub {
	return &Hub{clients: map[string]map[*websocket.Conn]struct{}{}, presence: presence}
}

func (h *Hub) Register(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	conns, ok := h.clients[userID]
	if !ok {
		conns = map[*websocket.Conn]struct{}{}
		h.clients[userID] = conns
	}
	conns[conn] = struct{}{}
	metrics.WSConnections.Set(float64(h.totalConnectionsLocked()))
}

func (h *Hub) Unregister(userID string, conn *websocket.Conn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	conns, ok := h.clients[userID]
	if !ok {
		return
	}
	delete(conns, conn)
	if len(conns) == 0 {
		delete(h.clients, userID)
	}
	metrics.WSConnections.Set(float64(h.totalConnectionsLocked()))
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
	conns, ok := h.clients[to]
	connSnapshot := make([]*websocket.Conn, 0, len(conns))
	if ok {
		for conn := range conns {
			connSnapshot = append(connSnapshot, conn)
		}
	}
	h.mu.RUnlock()
	if !ok || len(connSnapshot) == 0 {
		return nil
	}
	var firstErr error
	failed := make([]*websocket.Conn, 0)
	for _, conn := range connSnapshot {
		if conn == nil {
			continue
		}
		if err := conn.WriteMessage(websocket.TextMessage, raw); err != nil {
			if firstErr == nil {
				firstErr = err
			}
			failed = append(failed, conn)
			continue
		}
	}

	if len(failed) > 0 {
		h.mu.Lock()
		if live, exists := h.clients[to]; exists {
			for _, bad := range failed {
				delete(live, bad)
			}
			if len(live) == 0 {
				delete(h.clients, to)
			}
			metrics.WSConnections.Set(float64(h.totalConnectionsLocked()))
		}
		h.mu.Unlock()
	}

	return firstErr
}

func (h *Hub) totalConnectionsLocked() int {
	total := 0
	for _, conns := range h.clients {
		total += len(conns)
	}
	return total
}

func (h *Hub) StartRedisSubscriber(ctx context.Context, rdbSub service.PresenceService) {
	_ = ctx
	_ = rdbSub
	// In production, use dedicated redis pubsub subscription here for multi-instance routing.
}
