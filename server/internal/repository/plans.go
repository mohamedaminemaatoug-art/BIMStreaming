package repository

import (
	"context"
	"database/sql"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) GetPlanByName(ctx context.Context, name string) (*models.Plan, error) {
	var plan models.Plan
	if err := r.db.GetContext(ctx, &plan, `SELECT * FROM plans WHERE name=$1 LIMIT 1`, name); err != nil {
		return nil, err
	}
	return &plan, nil
}

func (r *Repository) GetUserSubscription(ctx context.Context, userID uuid.UUID) (*models.UserSubscription, error) {
	var sub models.UserSubscription
	if err := r.db.GetContext(ctx, &sub, `SELECT * FROM user_subscriptions WHERE user_id=$1 AND status='active' ORDER BY created_at DESC LIMIT 1`, userID); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &sub, nil
}

func (r *Repository) GetEffectivePlanForUser(ctx context.Context, userID uuid.UUID) (*models.Plan, error) {
	sub, err := r.GetUserSubscription(ctx, userID)
	if err != nil {
		return nil, err
	}
	if sub != nil {
		return r.GetPlanByID(ctx, sub.PlanID)
	}
	return r.GetPlanByName(ctx, "free")
}

func (r *Repository) GetPlanByID(ctx context.Context, planID uuid.UUID) (*models.Plan, error) {
	var plan models.Plan
	if err := r.db.GetContext(ctx, &plan, `SELECT * FROM plans WHERE id=$1 LIMIT 1`, planID); err != nil {
		return nil, err
	}
	return &plan, nil
}

func (r *Repository) CountUserCommunities(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	if err := r.db.GetContext(ctx, &count, `SELECT COUNT(*) FROM communities WHERE owner_id=$1 AND deleted_at IS NULL`, userID); err != nil {
		return 0, err
	}
	return count, nil
}

func (r *Repository) CountActiveRemoteSessions(ctx context.Context, userID uuid.UUID) (int, error) {
	var count int
	if err := r.db.GetContext(ctx, &count, `SELECT COUNT(*) FROM remote_sessions WHERE controller_id=$1 AND ended_at IS NULL`, userID); err != nil {
		return 0, err
	}
	return count, nil
}
