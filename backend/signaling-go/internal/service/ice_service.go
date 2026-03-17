package service

type ICEService interface {
	BuildICEServers() []map[string]interface{}
}

type iceService struct {
	stunURL      string
	turnURL      string
	turnUsername string
	turnPassword string
}

func NewICEService(stunURL, turnURL, turnUsername, turnPassword string) ICEService {
	return &iceService{
		stunURL:      stunURL,
		turnURL:      turnURL,
		turnUsername: turnUsername,
		turnPassword: turnPassword,
	}
}

func (s *iceService) BuildICEServers() []map[string]interface{} {
	return []map[string]interface{}{
		{"urls": []string{s.stunURL}},
		{
			"urls":       []string{s.turnURL},
			"username":   s.turnUsername,
			"credential": s.turnPassword,
		},
	}
}
