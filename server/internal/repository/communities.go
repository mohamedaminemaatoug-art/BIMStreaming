package repository

import (
	"context"
	"database/sql"
	"encoding/json"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (r *Repository) CreateCommunity(ctx context.Context, ownerID uuid.UUID, code, name, description, country string, isPublic bool) (*models.Community, error) {
	var c models.Community
	query := `
	INSERT INTO communities (code, name, description, country, owner_id, is_public)
	VALUES ($1,$2,$3,$4,$5,$6)
	RETURNING *`
	if err := r.db.GetContext(ctx, &c, query, strings.ToUpper(code), strings.TrimSpace(name), nullableString(description), nullableString(country), ownerID, isPublic); err != nil {
		return nil, err
	}
	_, err := r.db.ExecContext(ctx, `
	INSERT INTO community_members (community_id, user_id, role, status)
	VALUES ($1, $2, 'owner', 'active')
	ON CONFLICT (community_id, user_id) DO NOTHING`, c.ID, ownerID)
	if err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) ListCommunitiesForUser(ctx context.Context, userID uuid.UUID) ([]models.Community, error) {
	rows := []models.Community{}
	query := `
	SELECT c.*
	FROM communities c
	JOIN community_members cm ON cm.community_id=c.id
	WHERE cm.user_id=$1 AND cm.deleted_at IS NULL AND c.deleted_at IS NULL
	ORDER BY c.created_at DESC`
	if err := r.db.SelectContext(ctx, &rows, query, userID); err != nil {
		return nil, err
	}
	return rows, nil
}

func (r *Repository) GetCommunityByID(ctx context.Context, communityID uuid.UUID) (*models.Community, error) {
	var c models.Community
	if err := r.db.GetContext(ctx, &c, `SELECT * FROM communities WHERE id=$1 AND deleted_at IS NULL`, communityID); err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) GetCommunityByCode(ctx context.Context, code string) (*models.Community, error) {
	var c models.Community
	if err := r.db.GetContext(ctx, &c, `SELECT * FROM communities WHERE code=$1 AND deleted_at IS NULL`, strings.ToUpper(strings.TrimSpace(code))); err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) UpdateCommunity(ctx context.Context, communityID uuid.UUID, name, description, country string, isPublic *bool) (*models.Community, error) {
	setPublic := sql.NullBool{}
	if isPublic != nil {
		setPublic.Valid = true
		setPublic.Bool = *isPublic
	}
	var c models.Community
	query := `
	UPDATE communities
	SET name=COALESCE(NULLIF($2,''), name),
	    description=COALESCE($3, description),
	    country=COALESCE($4, country),
	    is_public=CASE WHEN $5::bool IS NULL THEN is_public ELSE $5 END,
	    updated_at=NOW()
	WHERE id=$1 AND deleted_at IS NULL
	RETURNING *`
	if err := r.db.GetContext(ctx, &c, query, communityID, strings.TrimSpace(name), nullableString(description), nullableString(country), setPublic); err != nil {
		return nil, err
	}
	return &c, nil
}

func (r *Repository) SoftDeleteCommunity(ctx context.Context, communityID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE communities SET deleted_at=NOW(), updated_at=NOW() WHERE id=$1`, communityID)
	return err
}

func (r *Repository) IsCommunityMember(ctx context.Context, communityID, userID uuid.UUID) (bool, string, error) {
	var role string
	err := r.db.GetContext(ctx, &role,
		`SELECT role FROM community_members WHERE community_id=$1 AND user_id=$2 AND deleted_at IS NULL LIMIT 1`,
		communityID, userID,
	)
	if err == sql.ErrNoRows {
		return false, "", nil
	}
	if err != nil {
		return false, "", err
	}
	return true, role, nil
}

func (r *Repository) ListCommunityMembers(ctx context.Context, communityID uuid.UUID) ([]models.CommunityMember, error) {
	rows := []models.CommunityMember{}
	if err := r.db.SelectContext(ctx, &rows,
		`SELECT * FROM community_members WHERE community_id=$1 AND deleted_at IS NULL ORDER BY joined_at ASC`,
		communityID,
	); err != nil {
		return nil, err
	}
	return rows, nil
}

func (r *Repository) UpdateCommunityMember(ctx context.Context, communityID, userID uuid.UUID, role string, departmentID *uuid.UUID) error {
	var deptArg interface{}
	if departmentID == nil {
		deptArg = nil
	} else {
		deptArg = *departmentID
	}
	_, err := r.db.ExecContext(ctx,
		`UPDATE community_members SET role=COALESCE(NULLIF($3,''), role), department_id=COALESCE($4, department_id), updated_at=NOW() WHERE community_id=$1 AND user_id=$2`,
		communityID, userID, role, deptArg,
	)
	return err
}

func (r *Repository) RemoveCommunityMember(ctx context.Context, communityID, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx,
		`UPDATE community_members SET deleted_at=NOW(), updated_at=NOW() WHERE community_id=$1 AND user_id=$2`,
		communityID, userID,
	)
	return err
}

func (r *Repository) AddCommunityMember(ctx context.Context, communityID, userID uuid.UUID, role string) error {
	_, err := r.db.ExecContext(ctx,
		`INSERT INTO community_members (community_id, user_id, role, status) VALUES ($1,$2,$3,'active')
		 ON CONFLICT (community_id, user_id)
		 DO UPDATE SET role=EXCLUDED.role, status='active', deleted_at=NULL, updated_at=NOW()`,
		communityID, userID, role,
	)
	return err
}

func (r *Repository) CreateJoinRequest(ctx context.Context, communityID, userID uuid.UUID, inviteCode, message string) (*models.JoinRequest, error) {
	var jr models.JoinRequest
	if err := r.db.GetContext(ctx, &jr,
		`INSERT INTO join_requests (community_id, user_id, invite_code_used, message, status)
		 VALUES ($1,$2,$3,$4,'pending')
		 ON CONFLICT (community_id, user_id)
		 DO UPDATE SET invite_code_used=EXCLUDED.invite_code_used, message=EXCLUDED.message, status='pending', reviewed_by=NULL, reviewed_at=NULL, updated_at=NOW()
		 RETURNING *`,
		communityID, userID, nullableString(inviteCode), nullableString(message),
	); err != nil {
		return nil, err
	}
	return &jr, nil
}

func (r *Repository) ListPendingJoinRequests(ctx context.Context, communityID uuid.UUID) ([]models.JoinRequest, error) {
	rows := []models.JoinRequest{}
	if err := r.db.SelectContext(ctx, &rows,
		`SELECT * FROM join_requests WHERE community_id=$1 AND status='pending' ORDER BY created_at ASC`,
		communityID,
	); err != nil {
		return nil, err
	}
	return rows, nil
}

func (r *Repository) UpdateJoinRequestStatus(ctx context.Context, requestID, reviewerID uuid.UUID, status string) (*models.JoinRequest, error) {
	var jr models.JoinRequest
	if err := r.db.GetContext(ctx, &jr,
		`UPDATE join_requests SET status=$2, reviewed_by=$3, reviewed_at=NOW(), updated_at=NOW() WHERE id=$1 RETURNING *`,
		requestID, status, reviewerID,
	); err != nil {
		return nil, err
	}
	return &jr, nil
}

func (r *Repository) GetJoinRequestByID(ctx context.Context, requestID uuid.UUID) (*models.JoinRequest, error) {
	var jr models.JoinRequest
	if err := r.db.GetContext(ctx, &jr, `SELECT * FROM join_requests WHERE id=$1`, requestID); err != nil {
		return nil, err
	}
	return &jr, nil
}

func (r *Repository) CreateDepartment(ctx context.Context, communityID uuid.UUID, name, country string) (*models.Department, error) {
	var dept models.Department
	if err := r.db.GetContext(ctx, &dept,
		`INSERT INTO departments (community_id, name, country) VALUES ($1,$2,$3) RETURNING *`,
		communityID, strings.TrimSpace(name), nullableString(country),
	); err != nil {
		return nil, err
	}
	return &dept, nil
}

func (r *Repository) UpdateDepartment(ctx context.Context, departmentID uuid.UUID, name, country string) (*models.Department, error) {
	var dept models.Department
	if err := r.db.GetContext(ctx, &dept,
		`UPDATE departments SET name=COALESCE(NULLIF($2,''), name), country=COALESCE($3, country), updated_at=NOW() WHERE id=$1 AND deleted_at IS NULL RETURNING *`,
		departmentID, strings.TrimSpace(name), nullableString(country),
	); err != nil {
		return nil, err
	}
	return &dept, nil
}

func (r *Repository) DeleteDepartment(ctx context.Context, departmentID uuid.UUID) error {
	if _, err := r.db.ExecContext(ctx,
		`UPDATE community_members SET department_id=NULL, updated_at=NOW() WHERE department_id=$1`,
		departmentID,
	); err != nil {
		return err
	}
	_, err := r.db.ExecContext(ctx, `UPDATE departments SET deleted_at=NOW(), updated_at=NOW() WHERE id=$1`, departmentID)
	return err
}

func (r *Repository) ListDepartments(ctx context.Context, communityID uuid.UUID) ([]models.Department, error) {
	depts := []models.Department{}
	if err := r.db.SelectContext(ctx, &depts, `SELECT * FROM departments WHERE community_id=$1 AND deleted_at IS NULL ORDER BY name`, communityID); err != nil {
		return nil, err
	}
	return depts, nil
}

func (r *Repository) DiscoverCommunities(ctx context.Context, q string, country string, limit int, cursor string) ([]models.Community, string, bool, error) {
	if limit <= 0 || limit > 50 {
		limit = 50
	}
	cursorID, err := parseCursorUUID(cursor)
	if err != nil {
		return nil, "", false, err
	}
	var cursorArg interface{}
	if cursorID == uuid.Nil {
		cursorArg = nil
	} else {
		cursorArg = cursorID
	}
	rows := []models.Community{}
	prefix := "%" + strings.ToLower(strings.TrimSpace(q)) + "%"
	query := `
	SELECT * FROM communities
	WHERE deleted_at IS NULL
	  AND is_public = true
	  AND (LOWER(name) LIKE $1 OR LOWER(code) LIKE $1 OR LOWER(COALESCE(description,'')) LIKE $1)
	  AND ($2::uuid IS NULL OR id < $2)
	ORDER BY created_at DESC
	LIMIT $3`
	if err := r.db.SelectContext(ctx, &rows, query, prefix, cursorArg, limit+1); err != nil {
		return nil, "", false, err
	}
	hasMore := len(rows) > limit
	if hasMore {
		rows = rows[:limit]
	}
	next := ""
	if hasMore && len(rows) > 0 {
		next = rows[len(rows)-1].ID.String()
	}
	return rows, next, hasMore, nil
}

func (r *Repository) CreateCommunityAnnouncement(ctx context.Context, communityID, authorID uuid.UUID, title, content string, pinned bool) (*models.CommunityAnnouncement, error) {
	var announcement models.CommunityAnnouncement
	if err := r.db.GetContext(ctx, &announcement, `
		INSERT INTO community_announcements (community_id, author_id, title, content, is_pinned)
		VALUES ($1,$2,$3,$4,$5)
		RETURNING *`, communityID, authorID, strings.TrimSpace(title), strings.TrimSpace(content), pinned); err != nil {
		return nil, err
	}
	return &announcement, nil
}

func (r *Repository) UpdateCommunityAnnouncement(ctx context.Context, announcementID uuid.UUID, title, content string, pinned *bool) (*models.CommunityAnnouncement, error) {
	var announcement models.CommunityAnnouncement
	if pinned == nil {
		if err := r.db.GetContext(ctx, &announcement, `
			UPDATE community_announcements
			SET title=COALESCE(NULLIF($2,''), title), content=COALESCE(NULLIF($3,''), content), updated_at=NOW()
			WHERE id=$1 AND deleted_at IS NULL
			RETURNING *`, announcementID, strings.TrimSpace(title), strings.TrimSpace(content)); err != nil {
			return nil, err
		}
		return &announcement, nil
	}
	if err := r.db.GetContext(ctx, &announcement, `
		UPDATE community_announcements
		SET title=COALESCE(NULLIF($2,''), title), content=COALESCE(NULLIF($3,''), content), is_pinned=$4, updated_at=NOW()
		WHERE id=$1 AND deleted_at IS NULL
		RETURNING *`, announcementID, strings.TrimSpace(title), strings.TrimSpace(content), *pinned); err != nil {
		return nil, err
	}
	return &announcement, nil
}

func (r *Repository) DeleteCommunityAnnouncement(ctx context.Context, announcementID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `UPDATE community_announcements SET deleted_at=NOW(), updated_at=NOW() WHERE id=$1`, announcementID)
	return err
}

func (r *Repository) ListCommunityAnnouncements(ctx context.Context, communityID uuid.UUID) ([]models.CommunityAnnouncement, error) {
	rows := []models.CommunityAnnouncement{}
	if err := r.db.SelectContext(ctx, &rows, `SELECT * FROM community_announcements WHERE community_id=$1 AND deleted_at IS NULL ORDER BY is_pinned DESC, created_at DESC`, communityID); err != nil {
		return nil, err
	}
	return rows, nil
}

func (r *Repository) CreateCommunityBan(ctx context.Context, communityID, userID, bannedBy uuid.UUID, reason string, expiresAt *time.Time) (*models.CommunityBan, error) {
	var ban models.CommunityBan
	if err := r.db.GetContext(ctx, &ban, `
		INSERT INTO community_bans (community_id, user_id, banned_by, reason, expires_at)
		VALUES ($1,$2,$3,$4,$5)
		RETURNING *`, communityID, userID, bannedBy, nullableString(reason), expiresAt); err != nil {
		return nil, err
	}
	return &ban, nil
}

func (r *Repository) DeleteCommunityBan(ctx context.Context, communityID, userID uuid.UUID) error {
	_, err := r.db.ExecContext(ctx, `DELETE FROM community_bans WHERE community_id=$1 AND user_id=$2`, communityID, userID)
	return err
}

func (r *Repository) ListCommunityBans(ctx context.Context, communityID uuid.UUID) ([]models.CommunityBan, error) {
	bans := []models.CommunityBan{}
	if err := r.db.SelectContext(ctx, &bans, `SELECT * FROM community_bans WHERE community_id=$1 ORDER BY created_at DESC`, communityID); err != nil {
		return nil, err
	}
	return bans, nil
}

func (r *Repository) InsertCommunityAuditLog(ctx context.Context, communityID, actorID uuid.UUID, action string, targetUserID *uuid.UUID, metadata any) error {
	var targetArg interface{}
	if targetUserID == nil {
		targetArg = nil
	} else {
		targetArg = *targetUserID
	}
	payload, err := json.Marshal(metadata)
	if err != nil {
		return err
	}
	_, err = r.db.ExecContext(ctx, `
		INSERT INTO community_audit_log (community_id, actor_id, action, target_user_id, metadata)
		VALUES ($1,$2,$3,$4,$5)`, communityID, actorID, strings.TrimSpace(action), targetArg, payload)
	return err
}

func (r *Repository) ListCommunityAuditLog(ctx context.Context, communityID uuid.UUID, limit int) ([]models.CommunityAuditLog, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	logs := []models.CommunityAuditLog{}
	if err := r.db.SelectContext(ctx, &logs, `SELECT * FROM community_audit_log WHERE community_id=$1 ORDER BY created_at DESC LIMIT $2`, communityID, limit); err != nil {
		return nil, err
	}
	return logs, nil
}
