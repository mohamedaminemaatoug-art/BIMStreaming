package storage

import (
	"bytes"
	"fmt"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"bimstreaming/server/internal/auth"

	"github.com/disintegration/imaging"
	"github.com/google/uuid"
	_ "golang.org/x/image/webp"
)

type AvatarService struct {
	storagePath string
	baseURL     string
	maxBytes    int64
}

func NewAvatarService(storagePath, baseURL string, maxUploadMB int64) *AvatarService {
	return &AvatarService{storagePath: storagePath, baseURL: strings.TrimRight(baseURL, "/"), maxBytes: maxUploadMB * 1024 * 1024}
}

func (s *AvatarService) EnsureStorage() error {
	return os.MkdirAll(s.storagePath, 0o755)
}

func (s *AvatarService) GravatarURL(email string) string {
	hash := auth.GravatarHash(email)
	return fmt.Sprintf("https://www.gravatar.com/avatar/%s?d=404", hash)
}

func (s *AvatarService) HasGravatar(email string) bool {
	url := s.GravatarURL(email)
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

func (s *AvatarService) SaveUploadedAvatar(file multipart.File, header *multipart.FileHeader, userID uuid.UUID) (string, error) {
	if header.Size > s.maxBytes {
		return "", fmt.Errorf("file too large")
	}
	allowed := map[string]bool{
		"image/jpeg": true,
		"image/png":  true,
		"image/webp": true,
	}
	mimeType := header.Header.Get("Content-Type")
	if !allowed[mimeType] {
		return "", fmt.Errorf("unsupported mime type")
	}
	buf, err := io.ReadAll(io.LimitReader(file, s.maxBytes+1))
	if err != nil {
		return "", err
	}
	if int64(len(buf)) > s.maxBytes {
		return "", fmt.Errorf("file too large")
	}
	img, err := imaging.Decode(bytes.NewReader(buf))
	if err != nil {
		return "", err
	}
	cropped := imaging.Fill(img, 256, 256, imaging.Center, imaging.Lanczos)

	filename := fmt.Sprintf("%s-%d.png", userID.String(), time.Now().UTC().UnixNano())
	absPath := filepath.Join(s.storagePath, filename)
	out, err := os.Create(absPath)
	if err != nil {
		return "", err
	}
	defer out.Close()
	if err := png.Encode(out, cropped); err != nil {
		return "", err
	}
	return s.baseURL + "/media/avatars/" + filename, nil
}

func (s *AvatarService) AvatarFilePath(filename string) string {
	return filepath.Join(s.storagePath, filepath.Clean(filename))
}

func (s *AvatarService) MaxUploadSize() int64 {
	return s.maxBytes
}
