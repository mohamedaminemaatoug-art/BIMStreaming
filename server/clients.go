package main

import (
	"sync"

	"github.com/gorilla/websocket"
)

type Client struct {
	ID   string
	Conn *websocket.Conn
	Send chan []byte
}

type ClientRegistry struct {
	mu      sync.RWMutex
	clients map[string]*Client
}

func NewClientRegistry() *ClientRegistry {
	return &ClientRegistry{clients: make(map[string]*Client)}
}

func (r *ClientRegistry) Add(c *Client) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.clients[c.ID] = c
}

func (r *ClientRegistry) Remove(clientID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.clients, clientID)
}

func (r *ClientRegistry) Get(clientID string) (*Client, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	c, ok := r.clients[clientID]
	return c, ok
}
