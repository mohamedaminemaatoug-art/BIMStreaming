package auth

import (
	"crypto/rand"
	"errors"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

type TokenManager struct {
	accessSecret  []byte
	refreshSecret []byte
}

type AccessClaims struct {
	DeviceID string `json:"device_id"`
	Role     string `json:"role"`
	jwt.RegisteredClaims
}

type PurposeClaims struct {
	Purpose string `json:"purpose"`
	jwt.RegisteredClaims
}

func NewTokenManager(accessSecret, refreshSecret string) *TokenManager {
	return &TokenManager{accessSecret: []byte(accessSecret), refreshSecret: []byte(refreshSecret)}
}

func (tm *TokenManager) GenerateAccessToken(userID, deviceID, role string, ttl time.Duration) (string, error) {
	claims := AccessClaims{
		DeviceID: deviceID,
		Role:     role,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(tm.accessSecret)
}

func (tm *TokenManager) ParseAccessToken(tokenStr string) (*AccessClaims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &AccessClaims{}, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected signing method")
		}
		return tm.accessSecret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*AccessClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid access token")
	}
	return claims, nil
}

func (tm *TokenManager) GeneratePurposeToken(subject, purpose string, ttl time.Duration) (string, error) {
	claims := PurposeClaims{
		Purpose: purpose,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   subject,
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			ExpiresAt: jwt.NewNumericDate(time.Now().UTC().Add(ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(tm.accessSecret)
}

func (tm *TokenManager) ParsePurposeToken(tokenStr string, expectedPurpose string) (*PurposeClaims, error) {
	token, err := jwt.ParseWithClaims(tokenStr, &PurposeClaims{}, func(token *jwt.Token) (interface{}, error) {
		if token.Method != jwt.SigningMethodHS256 {
			return nil, errors.New("unexpected signing method")
		}
		return tm.accessSecret, nil
	})
	if err != nil {
		return nil, err
	}
	claims, ok := token.Claims.(*PurposeClaims)
	if !ok || !token.Valid {
		return nil, errors.New("invalid purpose token")
	}
	if expectedPurpose != "" && claims.Purpose != expectedPurpose {
		return nil, fmt.Errorf("unexpected token purpose")
	}
	return claims, nil
}

func GenerateRandomBytes(n int) ([]byte, error) {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return nil, err
	}
	return buf, nil
}
