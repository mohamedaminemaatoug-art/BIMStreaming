package logger

import (
	"log"
)

type Logger struct{}

func New() *Logger {
	return &Logger{}
}

func (l *Logger) Info(msg string, kv ...interface{}) {
	log.Printf("INFO %s %v", msg, kv)
}

func (l *Logger) Error(msg string, kv ...interface{}) {
	log.Printf("ERROR %s %v", msg, kv)
}
