package repository

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgconn"
)

func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}

func (r *Repository) AreFriends(ctx context.Context, userA, userB uuid.UUID) (bool, error) {
	var exists bool
	if err := r.db.GetContext(ctx, &exists, `
		SELECT EXISTS(
			SELECT 1
			FROM friendships
			WHERE status='accepted'
			  AND deleted_at IS NULL
			  AND ((requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1))
		)`, userA, userB); err != nil {
		return false, err
	}
	return exists, nil
}

func (r *Repository) loadFriendshipPair(ctx context.Context, requesterID, addresseeID uuid.UUID) (*models.Friendship, error) {
	var existing models.Friendship
	if err := r.db.GetContext(
		ctx,
		&existing,
		`SELECT *
		 FROM friendships
		 WHERE LEAST(requester_id, addressee_id) = LEAST($1, $2)
		   AND GREATEST(requester_id, addressee_id) = GREATEST($1, $2)
		 ORDER BY created_at DESC
		 LIMIT 1`,
		requesterID,
		addresseeID,
	); err != nil {
		return nil, err
	}
	return &existing, nil
}

func (r *Repository) resolveFriendRequestPair(ctx context.Context, requesterID, addresseeID uuid.UUID) (*models.Friendship, error) {
	existing, err := r.loadFriendshipPair(ctx, requesterID, addresseeID)
	if err != nil {
		return nil, err
	}

	if existing.DeletedAt.Valid {
		var revived models.Friendship
		if err := r.db.GetContext(ctx, &revived,
			`UPDATE friendships
			 SET requester_id=$2,
			     addressee_id=$3,
			     status='pending',
			     deleted_at=NULL,
			     updated_at=NOW()
			 WHERE id=$1
			 RETURNING *`,
			existing.ID,
			requesterID,
			addresseeID,
		); err != nil {
			return nil, err
		}
		return &revived, nil
	}

	switch existing.Status {
	case "accepted":
		return nil, fmt.Errorf("already friends")
	case "blocked":
		return nil, fmt.Errorf("friendship is blocked")
	case "pending":
		if existing.RequesterID == addresseeID && existing.AddresseeID == requesterID {
			var accepted models.Friendship
			if err := r.db.GetContext(ctx, &accepted,
				`UPDATE friendships
				 SET status='accepted',
				     updated_at=NOW()
				 WHERE id=$1
				 RETURNING *`,
				existing.ID,
			); err != nil {
				return nil, err
			}
			return &accepted, nil
		}
		return existing, nil
	default:
		return existing, nil
	}
}

func (r *Repository) CreateFriendRequest(ctx context.Context, requesterID, addresseeID uuid.UUID) (*models.Friendship, error) {
	if requesterID == addresseeID {
		return nil, fmt.Errorf("cannot send friend request to yourself")
	}

	query := `
	INSERT INTO friendships (requester_id, addressee_id, status)
	VALUES ($1, $2, 'pending')
	ON CONFLICT (requester_id, addressee_id)
	DO UPDATE SET status='pending', updated_at=NOW(), deleted_at=NULL
	RETURNING *`
	var f models.Friendship
	if err := r.db.GetContext(ctx, &f, query, requesterID, addresseeID); err != nil {
		if isUniqueViolation(err) {
			return r.resolveFriendRequestPair(ctx, requesterID, addresseeID)
		}
		return nil, err
	}
	if f.Status == "pending" {
		return &f, nil
	}
	return r.resolveFriendRequestPair(ctx, requesterID, addresseeID)
}

func (r *Repository) GetFriendRequests(ctx context.Context, userID uuid.UUID) ([]models.Friendship, []models.Friendship, error) {
	incoming := []models.Friendship{}
	outgoing := []models.Friendship{}
	if err := r.db.SelectContext(ctx, &incoming, `SELECT * FROM friendships WHERE addressee_id=$1 AND status='pending' AND deleted_at IS NULL ORDER BY created_at DESC`, userID); err != nil {
		return nil, nil, err
	}
	if err := r.db.SelectContext(ctx, &outgoing, `SELECT * FROM friendships WHERE requester_id=$1 AND status='pending' AND deleted_at IS NULL ORDER BY created_at DESC`, userID); err != nil {
		return nil, nil, err
	}
	return incoming, outgoing, nil
}

func (r *Repository) GetFriendshipByID(ctx context.Context, id uuid.UUID) (*models.Friendship, error) {
	var f models.Friendship
	if err := r.db.GetContext(ctx, &f, `SELECT * FROM friendships WHERE id=$1 AND deleted_at IS NULL`, id); err != nil {
		return nil, err
	}
	return &f, nil
}

func (r *Repository) UpdateFriendshipStatus(ctx context.Context, id uuid.UUID, status string) (*models.Friendship, error) {
	var f models.Friendship
	if err := r.db.GetContext(ctx, &f,
		`UPDATE friendships SET status=$2, updated_at=NOW() WHERE id=$1 RETURNING *`,
		id, strings.TrimSpace(status),
	); err != nil {
		return nil, err
	}
	return &f, nil
}

func (r *Repository) DeleteFriendship(ctx context.Context, userID, otherID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE friendships SET deleted_at=NOW(), updated_at=NOW()
		 WHERE ((requester_id=$1 AND addressee_id=$2) OR (requester_id=$2 AND addressee_id=$1))
		   AND deleted_at IS NULL`,
		userID, otherID,
	)
	return err
}

func (r *Repository) ListAcceptedFriendIDs(ctx context.Context, userID uuid.UUID) ([]uuid.UUID, error) {
	ids := []uuid.UUID{}
	query := `
	SELECT CASE WHEN requester_id=$1 THEN addressee_id ELSE requester_id END AS friend_id
	FROM friendships
	WHERE status='accepted' AND deleted_at IS NULL AND (requester_id=$1 OR addressee_id=$1)`
	if err := r.db.SelectContext(ctx, &ids, query, userID); err != nil {
		return nil, err
	}
	return ids, nil
}

func (r *Repository) ListAcceptedFriends(ctx context.Context, userID uuid.UUID) ([]models.User, error) {
	users := []models.User{}
	query := `
	SELECT u.*
	FROM users u
	JOIN friendships f ON ((f.requester_id=$1 AND f.addressee_id=u.id) OR (f.addressee_id=$1 AND f.requester_id=u.id))
	WHERE f.status='accepted' AND f.deleted_at IS NULL AND u.deleted_at IS NULL
	ORDER BY u.username`
	if err := r.db.SelectContext(ctx, &users, query, userID); err != nil {
		return nil, err
	}
	return users, nil
}

func (r *Repository) ListBlockedFriends(ctx context.Context, userID uuid.UUID) ([]models.User, error) {
	users := []models.User{}
	query := `
	SELECT u.*
	FROM users u
	JOIN friendships f ON ((f.requester_id=$1 AND f.addressee_id=u.id) OR (f.addressee_id=$1 AND f.requester_id=u.id))
	WHERE f.status='blocked' AND f.deleted_at IS NULL AND u.deleted_at IS NULL
	ORDER BY u.username`
	if err := r.db.SelectContext(ctx, &users, query, userID); err != nil {
		return nil, err
	}
	return users, nil
}
