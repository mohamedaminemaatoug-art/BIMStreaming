package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"strings"
)

func GenerateOpaqueToken(byteLen int) (string, error) {
	buf := make([]byte, byteLen)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

func Sha256Hex(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func NormalizeIdentifier(identifier string) (kind string, normalized string) {
	trimmed := strings.TrimSpace(identifier)
	if strings.Contains(trimmed, "@") {
		return "email", strings.ToLower(trimmed)
	}
	compact := strings.ReplaceAll(trimmed, " ", "")
	if len(compact) > 0 {
		start := 0
		if compact[0] == '+' {
			start = 1
		}
		digitsOnly := true
		for _, ch := range compact[start:] {
			if ch < '0' || ch > '9' {
				digitsOnly = false
				break
			}
		}
		if digitsOnly && len(compact[start:]) > 0 {
			return "phone", compact
		}
	}
	return "username", trimmed
}
