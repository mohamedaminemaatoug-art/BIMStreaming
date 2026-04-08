package main

import (
	"log"
	"net/http"
	"os"
)

func main() {
	addr := ":8080"
	if fromEnv := os.Getenv("SERVER_ADDR"); fromEnv != "" {
		addr = fromEnv
	}

	clients := NewClientRegistry()
	sessions := NewSessionRegistry()
	router := NewRouter(clients, sessions)

	http.HandleFunc("/api/v1/ws", router.HandleWS)
	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	log.Printf("relay server listening on %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("server failed: %v", err)
	}
}
