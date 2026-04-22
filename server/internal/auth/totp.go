package auth

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base32"
	"encoding/binary"
	"fmt"
	"net/url"
	"strings"
	"time"
)

var totpEncoding = base32.StdEncoding.WithPadding(base32.NoPadding)

func GenerateTOTPSecret() (string, error) {
	raw, err := GenerateRandomBytes(20)
	if err != nil {
		return "", err
	}
	return strings.ToUpper(totpEncoding.EncodeToString(raw)), nil
}

func BuildTOTPURI(issuer, accountName, secret string) string {
	query := url.Values{}
	query.Set("secret", secret)
	query.Set("issuer", issuer)
	return fmt.Sprintf(
		"otpauth://totp/%s:%s?%s",
		url.PathEscape(issuer),
		url.PathEscape(accountName),
		query.Encode(),
	)
}

func VerifyTOTPCode(secret, code string, at time.Time, window int) bool {
	code = strings.TrimSpace(code)
	if len(code) != 6 {
		return false
	}
	rawSecret, err := totpEncoding.DecodeString(strings.ToUpper(strings.TrimSpace(secret)))
	if err != nil {
		return false
	}
	step := at.Unix() / 30
	for offset := -window; offset <= window; offset++ {
		if generateTOTPAt(rawSecret, step+int64(offset)) == code {
			return true
		}
	}
	return false
}

func GenerateBackupCode() (string, error) {
	raw, err := GenerateRandomBytes(6)
	if err != nil {
		return "", err
	}
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	chars := make([]byte, 8)
	for i := range chars {
		chars[i] = alphabet[int(raw[i%len(raw)])%len(alphabet)]
	}
	return string(chars), nil
}

func generateTOTPAt(secret []byte, counter int64) string {
	msg := make([]byte, 8)
	binary.BigEndian.PutUint64(msg, uint64(counter))
	mac := hmac.New(sha1.New, secret)
	_, _ = mac.Write(msg)
	hash := mac.Sum(nil)
	offset := hash[len(hash)-1] & 0x0f
	value := binary.BigEndian.Uint32(hash[offset:offset+4]) & 0x7fffffff
	return fmt.Sprintf("%06d", value%1000000)
}
