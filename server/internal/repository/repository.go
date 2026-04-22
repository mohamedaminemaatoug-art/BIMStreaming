package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
)

type Repository struct {
	db *sqlx.DB
}

func New(db *sqlx.DB) *Repository {
	return &Repository{db: db}
}

func (r *Repository) DB() *sqlx.DB {
	return r.db
}

func parseCursorUUID(cursor string) (uuid.UUID, error) {
	if strings.TrimSpace(cursor) == "" {
		return uuid.Nil, nil
	}
	id, err := uuid.Parse(cursor)
	if err != nil {
		return uuid.Nil, fmt.Errorf("invalid cursor")
	}
	return id, nil
}

func nullableString(value string) sql.NullString {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: trimmed, Valid: true}
}

func nullableUUID(id string) (uuid.NullUUID, error) {
	if strings.TrimSpace(id) == "" {
		return uuid.NullUUID{}, nil
	}
	parsed, err := uuid.Parse(id)
	if err != nil {
		return uuid.NullUUID{}, err
	}
	return uuid.NullUUID{UUID: parsed, Valid: true}, nil
}

func (r *Repository) Ping(ctx context.Context) error {
	return r.db.PingContext(ctx)
}
