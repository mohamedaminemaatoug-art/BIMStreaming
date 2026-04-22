package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/repository"
	wshub "bimstreaming/server/internal/ws"

	"github.com/google/uuid"
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
	clients      *ClientRegistry
	sessions     *SessionRegistry
	repo         *repository.Repository
	tokenManager *auth.TokenManager
	hub          *wshub.Hub
}

func NewRouter(clients *ClientRegistry, sessions *SessionRegistry, repo *repository.Repository, tokenManager *auth.TokenManager, hub *wshub.Hub) *Router {
	return &Router{clients: clients, sessions: sessions, repo: repo, tokenManager: tokenManager, hub: hub}
}

func (r *Router) HandleWS(w http.ResponseWriter, req *http.Request) {
	token := req.URL.Query().Get("token")
	authenticatedUserID := ""
	if token != "" && r.tokenManager != nil {
		if claims, err := r.tokenManager.ParseAccessToken(token); err == nil {
			authenticatedUserID = claims.RegisteredClaims.Subject
		}
	}

	clientID := req.URL.Query().Get("client_id")
	if clientID == "" {
		clientID = req.URL.Query().Get("user_id")
	}
	if clientID == "" && authenticatedUserID != "" {
		clientID = authenticatedUserID
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

	if authenticatedUserID != "" {
		r.hub.Register(authenticatedUserID, conn)
		go r.setPresenceAndBroadcast(authenticatedUserID, true)
	}

	go r.writeLoop(client)
	r.readLoop(client, authenticatedUserID)
}

func (r *Router) readLoop(c *Client, authenticatedUserID string) {
	defer func() {
		r.clients.Remove(c.ID)
		_ = c.Conn.Close()
		close(c.Send)
		if authenticatedUserID != "" {
			r.hub.Unregister(authenticatedUserID, c.Conn)
			go r.setPresenceAndBroadcast(authenticatedUserID, false)
		}
		log.Printf("client disconnected: %s", c.ID)
	}()

	for {
		messageType, msg, err := c.Conn.ReadMessage()
		if err != nil {
			return
		}
		if messageType != websocket.TextMessage {
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

func (r *Router) setPresenceAndBroadcast(userID string, online bool) {
	if r.repo == nil {
		return
	}
	parsed, err := uuid.Parse(userID)
	if err != nil {
		return
	}
	ctx := context.Background()
	if err := r.repo.SetOnlineStatus(ctx, parsed, online); err != nil {
		log.Printf("presence update failed: %v", err)
		return
	}
	friendIDs, err := r.repo.ListAcceptedFriendIDs(ctx, parsed)
	if err != nil {
		return
	}
	eventType := "user:offline"
	if online {
		eventType = "user:online"
	}
	targets := make([]string, 0, len(friendIDs)+1)
	targets = append(targets, userID)
	for _, fid := range friendIDs {
		targets = append(targets, fid.String())
	}
	r.hub.PublishToMany(targets, eventType, map[string]string{"user_id": userID})
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
		if err := c.Conn.WriteMessage(websocket.TextMessage, msg); err != nil {
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
