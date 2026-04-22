package repository

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

type AdminUserFilters struct {
	Query    string
	Verified *bool
	Banned   *bool
}

type PlatformStats struct {
	Users          int `json:"users"`
	Communities    int `json:"communities"`
	SessionsTotal  int `json:"sessions_total"`
	SessionsActive int `json:"sessions_active"`
}

func (r *Repository) ListUsersAdmin(ctx context.Context, page, limit int, filters AdminUserFilters) ([]models.User, int, error) {
	if page <= 0 {
		page = 1
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	offset := (page - 1) * limit
	clauses := []string{"deleted_at IS NULL"}
	args := []interface{}{}
	idx := 1
	if strings.TrimSpace(filters.Query) != "" {
		clauses = append(clauses, fmt.Sprintf("(LOWER(username) LIKE $%d OR LOWER(email) LIKE $%d)", idx, idx))
		args = append(args, "%"+strings.ToLower(strings.TrimSpace(filters.Query))+"%")
		idx++
	}
	if filters.Verified != nil {
		clauses = append(clauses, fmt.Sprintf("is_verified = $%d", idx))
		args = append(args, *filters.Verified)
		idx++
	}
	if filters.Banned != nil {
		clauses = append(clauses, fmt.Sprintf("is_banned = $%d", idx))
		args = append(args, *filters.Banned)
		idx++
	}
	where := strings.Join(clauses, " AND ")
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM users WHERE %s", where)
	var total int
	if err := r.db.GetContext(ctx, &total, countQuery, args...); err != nil {
		return nil, 0, err
	}
	args = append(args, limit, offset)
	query := fmt.Sprintf("SELECT * FROM users WHERE %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d", where, idx, idx+1)
	rows := []models.User{}
	if err := r.db.SelectContext(ctx, &rows, query, args...); err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

func (r *Repository) SetUserBan(ctx context.Context, userID uuid.UUID, banned bool, reason string) error {
	if banned {
		_, err := r.db.ExecContext(ctx, `UPDATE users SET is_banned=true, ban_reason=$2, updated_at=NOW() WHERE id=$1`, userID, nullableString(reason))
		return err
	}
	_, err := r.db.ExecContext(ctx, `UPDATE users SET is_banned=false, ban_reason=NULL, updated_at=NOW() WHERE id=$1`, userID)
	return err
}

func (r *Repository) SetUserEmailVerified(ctx context.Context, userID uuid.UUID, verified bool) error {
	_, err := r.db.ExecContext(ctx, `UPDATE users SET is_verified=$2, updated_at=NOW() WHERE id=$1`, userID, verified)
	return err
}

func (r *Repository) ListCommunitiesAdmin(ctx context.Context, page, limit int, queryText string) ([]models.Community, int, error) {
	if page <= 0 {
		page = 1
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	offset := (page - 1) * limit
	clauses := []string{"deleted_at IS NULL"}
	args := []interface{}{}
	idx := 1
	if strings.TrimSpace(queryText) != "" {
		clauses = append(clauses, fmt.Sprintf("(LOWER(name) LIKE $%d OR LOWER(code) LIKE $%d)", idx, idx))
		args = append(args, "%"+strings.ToLower(strings.TrimSpace(queryText))+"%")
		idx++
	}
	where := strings.Join(clauses, " AND ")
	countQuery := fmt.Sprintf("SELECT COUNT(*) FROM communities WHERE %s", where)
	var total int
	if err := r.db.GetContext(ctx, &total, countQuery, args...); err != nil {
		return nil, 0, err
	}
	args = append(args, limit, offset)
	listQuery := fmt.Sprintf("SELECT * FROM communities WHERE %s ORDER BY created_at DESC LIMIT $%d OFFSET $%d", where, idx, idx+1)
	rows := []models.Community{}
	if err := r.db.SelectContext(ctx, &rows, listQuery, args...); err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

func (r *Repository) ListRemoteSessionsAdmin(ctx context.Context, page, limit int, activeOnly bool) ([]models.RemoteSession, int, error) {
	if page <= 0 {
		page = 1
	}
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	offset := (page - 1) * limit
	where := "1=1"
	if activeOnly {
		where = "ended_at IS NULL"
	}
	var total int
	if err := r.db.GetContext(ctx, &total, "SELECT COUNT(*) FROM remote_sessions WHERE "+where); err != nil {
		return nil, 0, err
	}
	rows := []models.RemoteSession{}
	if err := r.db.SelectContext(ctx, &rows, "SELECT * FROM remote_sessions WHERE "+where+" ORDER BY created_at DESC LIMIT $1 OFFSET $2", limit, offset); err != nil {
		return nil, 0, err
	}
	return rows, total, nil
}

func (r *Repository) GetPlatformStats(ctx context.Context) (*PlatformStats, error) {
	stats := &PlatformStats{}
	if err := r.db.GetContext(ctx, &stats.Users, `SELECT COUNT(*) FROM users WHERE deleted_at IS NULL`); err != nil {
		return nil, err
	}
	if err := r.db.GetContext(ctx, &stats.Communities, `SELECT COUNT(*) FROM communities WHERE deleted_at IS NULL`); err != nil {
		return nil, err
	}
	if err := r.db.GetContext(ctx, &stats.SessionsTotal, `SELECT COUNT(*) FROM remote_sessions`); err != nil {
		return nil, err
	}
	if err := r.db.GetContext(ctx, &stats.SessionsActive, `SELECT COUNT(*) FROM remote_sessions WHERE ended_at IS NULL`); err != nil {
		return nil, err
	}
	return stats, nil
}

func (r *Repository) GetAdminUserDetail(ctx context.Context, userID uuid.UUID) (*models.User, *models.UserSubscription, *models.Plan, []models.AuditLog, error) {
	user, err := r.GetUserByID(ctx, userID)
	if err != nil {
		return nil, nil, nil, nil, err
	}
	sub, err := r.GetUserSubscription(ctx, userID)
	if err != nil {
		return nil, nil, nil, nil, err
	}
	var plan *models.Plan
	if sub != nil {
		plan, err = r.GetPlanByID(ctx, sub.PlanID)
		if err != nil && err != sql.ErrNoRows {
			return nil, nil, nil, nil, err
		}
	}
	audits, _, _, err := r.ListAuditLogs(ctx, AuditFilters{UserID: &userID, DateFrom: ptrTime(time.Now().UTC().Add(-180 * 24 * time.Hour))}, "", 100)
	if err != nil {
		return nil, nil, nil, nil, err
	}
	return user, sub, plan, audits, nil
}

func ptrTime(v time.Time) *time.Time {
	return &v
}
