package main

import "sync"

type Session struct {
	ID           string
	ControllerID string
	AgentID      string
}

type SessionRegistry struct {
	mu       sync.RWMutex
	sessions map[string]*Session
}

func NewSessionRegistry() *SessionRegistry {
	return &SessionRegistry{sessions: make(map[string]*Session)}
}

func (r *SessionRegistry) Upsert(s *Session) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.sessions[s.ID] = s
}

func (r *SessionRegistry) Delete(sessionID string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.sessions, sessionID)
}

func (r *SessionRegistry) Get(sessionID string) (*Session, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	s, ok := r.sessions[sessionID]
	return s, ok
}

func (r *SessionRegistry) FindPeer(clientID string) (string, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	for _, s := range r.sessions {
		if s.ControllerID == clientID {
			return s.AgentID, true
		}
		if s.AgentID == clientID {
			return s.ControllerID, true
		}
	}
	return "", false
}
