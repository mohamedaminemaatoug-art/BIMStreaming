package auth

import (
	"crypto/md5"
	"encoding/hex"
	"errors"
	"regexp"
	"sort"
	"strings"

	"crypto/sha256"
	"io"

	"golang.org/x/crypto/hkdf"
)

var (
	emailRegex         = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)
	uppercaseRegex     = regexp.MustCompile(`[A-Z]`)
	numberRegex        = regexp.MustCompile(`[0-9]`)
	specialCharRegex   = regexp.MustCompile(`[^A-Za-z0-9]`)
	verificationCodeRe = regexp.MustCompile(`^[0-9]{6}$`)
)

func ValidateEmail(email string) bool {
	return emailRegex.MatchString(strings.TrimSpace(email))
}

func ValidatePasswordStrength(password string) error {
	if len(password) < 8 {
		return errors.New("password must be at least 8 characters")
	}
	if !uppercaseRegex.MatchString(password) {
		return errors.New("password must contain at least one uppercase letter")
	}
	if !numberRegex.MatchString(password) {
		return errors.New("password must contain at least one number")
	}
	if !specialCharRegex.MatchString(password) {
		return errors.New("password must contain at least one special character")
	}
	return nil
}

func ValidateVerificationCode(code string) bool {
	return verificationCodeRe.MatchString(strings.TrimSpace(code))
}

func GravatarHash(email string) string {
	normalized := strings.ToLower(strings.TrimSpace(email))
	sum := md5.Sum([]byte(normalized))
	return hex.EncodeToString(sum[:])
}

func DeriveDMKey(secret []byte, userA, userB string) ([]byte, error) {
	ids := []string{userA, userB}
	sort.Strings(ids)
	info := []byte("dm:" + ids[0] + ":" + ids[1])
	kdf := hkdf.New(sha256.New, secret, nil, info)
	key := make([]byte, 32)
	if _, err := io.ReadFull(kdf, key); err != nil {
		return nil, err
	}
	return key, nil
}
