package storage

import (
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
)

type AttachmentService struct {
	storagePath string
	baseURL     string
	maxBytes    int64
}

func NewAttachmentService(storagePath, baseURL string, maxUploadMB int64) *AttachmentService {
	return &AttachmentService{storagePath: storagePath, baseURL: strings.TrimRight(baseURL, "/"), maxBytes: maxUploadMB * 1024 * 1024}
}

func (s *AttachmentService) EnsureStorage() error {
	return os.MkdirAll(s.storagePath, 0o755)
}

func (s *AttachmentService) StoragePath() string {
	return s.storagePath
}

func (s *AttachmentService) SaveAttachment(file multipart.File, header *multipart.FileHeader, ownerID uuid.UUID) (string, string, int64, error) {
	if header.Size > s.maxBytes {
		return "", "", 0, fmt.Errorf("file too large")
	}
	filename := fmt.Sprintf("%s_%s", ownerID.String(), filepath.Base(header.Filename))
	filename = strings.ReplaceAll(filename, string(os.PathSeparator), "_")
	filename = strings.ReplaceAll(filename, "..", "_")
	absPath := filepath.Join(s.storagePath, fmt.Sprintf("%d_%s", time.Now().UnixNano(), filename))
	out, err := os.Create(absPath)
	if err != nil {
		return "", "", 0, err
	}
	defer out.Close()
	written, err := io.Copy(out, io.LimitReader(file, s.maxBytes+1))
	if err != nil {
		return "", "", 0, err
	}
	if written > s.maxBytes {
		return "", "", 0, fmt.Errorf("file too large")
	}
	publicURL := s.baseURL + "/media/attachments/" + filepath.Base(absPath)
	return absPath, publicURL, written, nil
}
