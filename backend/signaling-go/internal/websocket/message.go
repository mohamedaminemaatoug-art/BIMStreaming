package websocket

type SignalType string

const (
	ConnectionRequest SignalType = "connection_request"
	ConnectionAccept  SignalType = "connection_accept"
	ConnectionReject  SignalType = "connection_reject"
	ICECandidate      SignalType = "ice_candidate"
	SessionEnd        SignalType = "session_end"
)

type Message struct {
	Type      SignalType             `json:"type"`
	SessionID string                 `json:"session_id,omitempty"`
	From      string                 `json:"from"`
	To        string                 `json:"to"`
	Payload   map[string]interface{} `json:"payload,omitempty"`
}
