package main

import (
	"encoding/json"
	"log"
	"net/http"

	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type Envelope struct {
	Type      string                 `json:"type"`
	SessionID string                 `json:"session_id,omitempty"`
	From      string                 `json:"from,omitempty"`
	To        string                 `json:"to,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
	Payload   map[string]interface{} `json:"payload,omitempty"`
}

type Router struct {
	clients  *ClientRegistry
	sessions *SessionRegistry
}

func NewRouter(clients *ClientRegistry, sessions *SessionRegistry) *Router {
	return &Router{clients: clients, sessions: sessions}
}

func (r *Router) HandleWS(w http.ResponseWriter, req *http.Request) {
	clientID := req.URL.Query().Get("client_id")
	if clientID == "" {
		clientID = req.URL.Query().Get("user_id")
	}
	if clientID == "" {
		http.Error(w, "client_id is required", http.StatusBadRequest)
		return
	}

	conn, err := upgrader.Upgrade(w, req, nil)
	if err != nil {
		log.Printf("ws upgrade failed: %v", err)
		return
	}

	client := &Client{ID: clientID, Conn: conn, Send: make(chan []byte, 256)}
	r.clients.Add(client)
	log.Printf("client connected: %s", clientID)

	go r.writeLoop(client)
	r.readLoop(client)
}

func (r *Router) readLoop(c *Client) {
	defer func() {
		r.clients.Remove(c.ID)
		_ = c.Conn.Close()
		close(c.Send)
		log.Printf("client disconnected: %s", c.ID)
	}()

	for {
		messageType, msg, err := c.Conn.ReadMessage()
		if err != nil {
			return
		}

		if messageType == websocket.BinaryMessage {
			r.handleBinaryVideoFrame(c.ID, msg) // PHASE 2: relay binary video frames separately from JSON control signals
			continue
		}

		var env Envelope
		if err := json.Unmarshal(msg, &env); err != nil {
			continue
		}

		switch env.Type {
		case "register":
			r.handleRegister(c.ID, env)
		case "connection_request":
			r.handleConnectionRequest(msg, env)
		case "connection_accept", "connection_reject":
			r.handleConnectionResponse(msg, env)
		case "session_message":
			r.handleSessionMessage(msg, env)
		default:
			// Relay-only server: ignore unknown messages.
		}
	}
}

func (r *Router) handleBinaryVideoFrame(fromClientID string, msg []byte) {
	if len(msg) < 8 {
		return
	}
	if msg[0] != 0xFE || msg[1] != 0xFF {
		return
	}
	toClientID, ok := r.sessions.FindPeer(fromClientID)
	if !ok || toClientID == "" {
		log.Printf("relay: peer not found, skipping binary frame from %s", fromClientID)
		return
	}
	target, ok := r.clients.Get(toClientID)
	if !ok {
		return
	}
	copyMsg := append([]byte(nil), msg...)
	select {
	case target.Send <- copyMsg:
	default:
		log.Printf("dropping binary frame for %s: outbound queue full", toClientID)
	}
}

func (r *Router) handleRegister(clientID string, env Envelope) {
	payload := env.Payload
	if payload == nil && env.Data != nil {
		payload = env.Data
	}
	if payload == nil {
		return
	}
	sessionID, _ := payload["sessionId"].(string)
	if sessionID == "" {
		sessionID, _ = payload["session_id"].(string)
	}
	if sessionID == "" {
		return
	}
	role, _ := payload["role"].(string)
	peerID, _ := payload["peerId"].(string)

	if existing, ok := r.sessions.Get(sessionID); ok {
		s := *existing
		if role == "host" {
			s.ControllerID = clientID
			if peerID != "" {
				s.AgentID = peerID
			}
		} else if role == "viewer" {
			s.AgentID = clientID
			if peerID != "" {
				s.ControllerID = peerID
			}
		}
		r.sessions.Upsert(&s)
		return
	}

	s := &Session{ID: sessionID}
	if role == "host" {
		s.ControllerID = clientID
		s.AgentID = peerID
	} else if role == "viewer" {
		s.AgentID = clientID
		s.ControllerID = peerID
	}
	r.sessions.Upsert(s)
}

func (r *Router) writeLoop(c *Client) {
	for msg := range c.Send {
		messageType := websocket.TextMessage
		if len(msg) >= 2 && msg[0] == 0xFE && msg[1] == 0xFF {
			messageType = websocket.BinaryMessage // PHASE 2: preserve binary frames over relay
		}
		if err := c.Conn.WriteMessage(messageType, msg); err != nil {
			return
		}
	}
}

func (r *Router) handleConnectionRequest(raw []byte, env Envelope) {
	if env.SessionID != "" && env.From != "" && env.To != "" {
		r.sessions.Upsert(&Session{ID: env.SessionID, ControllerID: env.From, AgentID: env.To})
	}
	r.forwardTo(env.To, raw)
}

func (r *Router) handleConnectionResponse(raw []byte, env Envelope) {
	r.forwardTo(env.To, raw)
}

func (r *Router) handleSessionMessage(raw []byte, env Envelope) {
	if env.Data == nil {
		return
	}
	to, _ := env.Data["toUserId"].(string)
	if to == "" {
		return
	}
	r.forwardTo(to, raw)
}

func (r *Router) forwardTo(clientID string, msg []byte) {
	target, ok := r.clients.Get(clientID)
	if !ok {
		return
	}
	select {
	case target.Send <- msg:
	default:
		log.Printf("dropping message for %s: outbound queue full", clientID)
	}
}
