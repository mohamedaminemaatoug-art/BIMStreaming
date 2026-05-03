package handlers

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (a *App) CreateCommunity(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		IsPublic    bool   `json:"is_public"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Name) == "" {
		badRequest(w, "name is required")
		return
	}
	code, err := generateCommunityCode(8)
	if err != nil {
		internalError(w, "failed to generate invite code")
		return
	}
	community, err := a.Repo.CreateCommunity(r.Context(), userID, code, body.Name, body.Description, "", body.IsPublic)
	if err != nil {
		internalError(w, "failed to create community")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), community.ID, userID, "community_created", nil, map[string]interface{}{"is_public": body.IsPublic})
	writeJSON(w, http.StatusCreated, community)
}

func (a *App) ListCommunities(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communities, err := a.Repo.ListCommunitiesForUser(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to list communities")
		return
	}
	type communityRow struct {
		*models.Community
		MemberCount int `json:"member_count"`
	}
	result := make([]communityRow, len(communities))
	for i := range communities {
		count, _ := a.Repo.CountCommunityMembers(r.Context(), communities[i].ID)
		result[i] = communityRow{Community: &communities[i], MemberCount: count}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": result})
}

func (a *App) DiscoverCommunities(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	_ = userID
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	country := strings.TrimSpace(r.URL.Query().Get("country"))
	limit := intQueryDefault(r, "limit", 25)
	cursor := strings.TrimSpace(r.URL.Query().Get("cursor"))
	communities, next, hasMore, err := a.Repo.DiscoverCommunities(r.Context(), query, country, limit, cursor)
	if err != nil {
		internalError(w, "failed to discover communities")
		return
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: communities, NextCursor: next, HasMore: hasMore})
}

func (a *App) GetCommunity(w http.ResponseWriter, r *http.Request) {
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	community, err := a.Repo.GetCommunityByID(r.Context(), communityID)
	if err != nil {
		notFound(w, "community not found")
		return
	}
	members, _ := a.Repo.ListCommunityMembers(r.Context(), communityID)
	departments, _ := a.Repo.ListDepartments(r.Context(), communityID)
	response := map[string]interface{}{"community": community, "members": members, "departments": departments}
	if currentUser, err := currentUserID(r); err == nil {
		if _, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, currentUser); err == nil {
			response["my_role"] = role
		}
	}
	writeJSON(w, http.StatusOK, response)
}

func (a *App) UpdateCommunity(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	ok, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, userID)
	if err != nil || !ok {
		forbidden(w, "not a community member")
		return
	}
	if role != "owner" && role != "admin" {
		forbidden(w, "only owner/admin can update")
		return
	}
	var body struct {
		Name        string `json:"name"`
		Description string `json:"description"`
		Country     string `json:"country"`
		IsPublic    *bool  `json:"is_public"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	community, err := a.Repo.UpdateCommunity(r.Context(), communityID, body.Name, body.Description, body.Country, body.IsPublic)
	if err != nil {
		internalError(w, "failed to update community")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, userID, "community_updated", nil, body)
	writeJSON(w, http.StatusOK, community)
}

func (a *App) DeleteCommunity(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	community, err := a.Repo.GetCommunityByID(r.Context(), communityID)
	if err != nil {
		notFound(w, "community not found")
		return
	}
	if community.OwnerID != userID {
		forbidden(w, "only owner can delete community")
		return
	}
	if err := a.Repo.SoftDeleteCommunity(r.Context(), communityID); err != nil {
		internalError(w, "failed to delete community")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, userID, "community_deleted", nil, map[string]interface{}{"deleted_at": time.Now().UTC()})
	writeJSON(w, http.StatusOK, map[string]string{"message": "community deleted"})
}

func (a *App) ListCommunityMembers(w http.ResponseWriter, r *http.Request) {
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	members, err := a.Repo.ListCommunityMembers(r.Context(), communityID)
	if err != nil {
		internalError(w, "failed to list members")
		return
	}
	userIDs := make([]uuid.UUID, 0, len(members))
	for _, member := range members {
		userIDs = append(userIDs, member.UserID)
	}
	users, err := a.Repo.GetUsersByIDs(r.Context(), userIDs)
	if err != nil {
		internalError(w, "failed to load member profiles")
		return
	}
	statuses, err := a.Repo.ListStatusesByUserIDs(r.Context(), userIDs)
	if err != nil {
		internalError(w, "failed to load member status")
		return
	}
	usersByID := make(map[uuid.UUID]interface{}, len(users))
	for _, user := range users {
		displayName := strings.TrimSpace(user.DisplayName.String)
		if displayName == "" {
			displayName = user.Username
		}
		usersByID[user.ID] = map[string]interface{}{
			"id":           user.ID,
			"username":     user.Username,
			"email":        user.Email,
			"display_name": displayName,
			"avatar_url":   user.AvatarURL,
			"is_online":    user.IsOnline,
			"device_id":    user.DeviceID,
		}
	}
	statusByID := make(map[uuid.UUID]interface{}, len(statuses))
	for _, status := range statuses {
		statusByID[status.UserID] = map[string]interface{}{
			"availability": status.Availability,
			"message":      status.Message,
			"emoji":        status.Emoji,
		}
	}

	enriched := make([]map[string]interface{}, 0, len(members))
	for _, member := range members {
		user := usersByID[member.UserID]
		username := ""
		displayName := ""
		avatarURL := ""
		isOnline := false
		if userMap, ok := user.(map[string]interface{}); ok {
			username = strings.TrimSpace(fmt.Sprint(userMap["username"]))
			displayName = strings.TrimSpace(fmt.Sprint(userMap["display_name"]))
			avatarURL = strings.TrimSpace(fmt.Sprint(userMap["avatar_url"]))
			if online, ok := userMap["is_online"].(bool); ok {
				isOnline = online
			}
		}
		enriched = append(enriched, map[string]interface{}{
			"id":            member.ID,
			"community_id":  member.CommunityID,
			"user_id":       member.UserID,
			"department_id": member.DepartmentID,
			"role":          member.Role,
			"status":        member.Status,
			"joined_at":     member.JoinedAt,
			"username":      username,
			"display_name":  displayName,
			"avatar_url":    avatarURL,
			"is_online":     isOnline,
			"user":          user,
			"presence":      statusByID[member.UserID],
		})
	}

	writeJSON(w, http.StatusOK, map[string]interface{}{"data": enriched})
}

func (a *App) UpdateCommunityMember(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	targetID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	ok, actorRole, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || !ok {
		forbidden(w, "not a member")
		return
	}
	_, targetRole, err := a.Repo.IsCommunityMember(r.Context(), communityID, targetID)
	if err != nil {
		forbidden(w, "target is not a member")
		return
	}
	var body struct {
		Role         string `json:"role"`
		DepartmentID string `json:"department_id"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	if !canManageRole(actorRole, targetRole) || !canPromoteTo(actorRole, body.Role) {
		forbidden(w, "insufficient permissions")
		return
	}
	var deptID *uuid.UUID
	if strings.TrimSpace(body.DepartmentID) != "" {
		parsed, err := uuid.Parse(body.DepartmentID)
		if err != nil {
			badRequest(w, "invalid department_id")
			return
		}
		deptID = &parsed
	}
	if err := a.Repo.UpdateCommunityMember(r.Context(), communityID, targetID, body.Role, deptID); err != nil {
		internalError(w, "failed to update member")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "member_role_updated", &targetID, map[string]interface{}{"role": body.Role, "department_id": body.DepartmentID})
	a.Hub.PublishToUser(targetID.String(), "community:member_role", map[string]interface{}{"community_id": communityID, "role": body.Role})
	writeJSON(w, http.StatusOK, map[string]string{"message": "member updated"})
}

func (a *App) RemoveCommunityMember(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	targetID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	_, actorRole, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil {
		forbidden(w, "not allowed")
		return
	}
	_, targetRole, err := a.Repo.IsCommunityMember(r.Context(), communityID, targetID)
	if err != nil {
		forbidden(w, "not allowed")
		return
	}
	if !canManageRole(actorRole, targetRole) {
		forbidden(w, "cannot remove this member")
		return
	}
	if err := a.Repo.RemoveCommunityMember(r.Context(), communityID, targetID); err != nil {
		internalError(w, "failed to remove member")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "member_removed", &targetID, nil)
	writeJSON(w, http.StatusOK, map[string]string{"message": "member removed"})
}

func (a *App) ListCommunityAnnouncements(w http.ResponseWriter, r *http.Request) {
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	announcements, err := a.Repo.ListCommunityAnnouncements(r.Context(), communityID)
	if err != nil {
		internalError(w, "failed to load announcements")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": announcements})
}

func (a *App) CreateCommunityAnnouncement(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Title   string `json:"title"`
		Content string `json:"content"`
		Pinned  bool   `json:"pinned"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Title) == "" || strings.TrimSpace(body.Content) == "" {
		badRequest(w, "title and content are required")
		return
	}
	announcement, err := a.Repo.CreateCommunityAnnouncement(r.Context(), communityID, actorID, body.Title, body.Content, body.Pinned)
	if err != nil {
		internalError(w, "failed to create announcement")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "announcement_created", nil, map[string]interface{}{"announcement_id": announcement.ID, "title": body.Title})
	members, _ := a.Repo.ListCommunityMembers(r.Context(), communityID)
	targets := make([]string, 0, len(members))
	for _, member := range members {
		targets = append(targets, member.UserID.String())
	}
	a.Hub.PublishToMany(targets, "community:announcement", map[string]interface{}{"community_id": communityID, "announcement": announcement})
	writeJSON(w, http.StatusCreated, announcement)
}

func (a *App) UpdateCommunityAnnouncement(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	announcementID, err := parseUUIDParam(r, "announcement_id")
	if err != nil {
		badRequest(w, "invalid announcement id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Title   string `json:"title"`
		Content string `json:"content"`
		Pinned  *bool  `json:"pinned"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	announcement, err := a.Repo.UpdateCommunityAnnouncement(r.Context(), announcementID, body.Title, body.Content, body.Pinned)
	if err != nil {
		internalError(w, "failed to update announcement")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "announcement_updated", nil, map[string]interface{}{"announcement_id": announcementID})
	writeJSON(w, http.StatusOK, announcement)
}

func (a *App) DeleteCommunityAnnouncement(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	announcementID, err := parseUUIDParam(r, "announcement_id")
	if err != nil {
		badRequest(w, "invalid announcement id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	if err := a.Repo.DeleteCommunityAnnouncement(r.Context(), announcementID); err != nil {
		internalError(w, "failed to delete announcement")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "announcement_deleted", nil, map[string]interface{}{"announcement_id": announcementID})
	writeJSON(w, http.StatusOK, map[string]string{"message": "announcement deleted"})
}

func (a *App) ListCommunityBans(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	bans, err := a.Repo.ListCommunityBans(r.Context(), communityID)
	if err != nil {
		internalError(w, "failed to list bans")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": bans})
}

func (a *App) BanCommunityMember(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	targetID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Reason    string `json:"reason"`
		ExpiresAt string `json:"expires_at"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	var expiresAt *time.Time
	if strings.TrimSpace(body.ExpiresAt) != "" {
		parsed, err := time.Parse(time.RFC3339, strings.TrimSpace(body.ExpiresAt))
		if err != nil {
			badRequest(w, "invalid expires_at")
			return
		}
		expiresAt = &parsed
	}
	ban, err := a.Repo.CreateCommunityBan(r.Context(), communityID, targetID, actorID, body.Reason, expiresAt)
	if err != nil {
		internalError(w, "failed to ban member")
		return
	}
	_ = a.Repo.RemoveCommunityMember(r.Context(), communityID, targetID)
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "member_banned", &targetID, map[string]interface{}{"reason": body.Reason})
	a.Hub.PublishToUser(targetID.String(), "community:banned", map[string]interface{}{"community_id": communityID, "reason": body.Reason})
	writeJSON(w, http.StatusCreated, ban)
}

func (a *App) UnbanCommunityMember(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	targetID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	if err := a.Repo.DeleteCommunityBan(r.Context(), communityID, targetID); err != nil {
		internalError(w, "failed to unban member")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "member_unbanned", &targetID, nil)
	writeJSON(w, http.StatusOK, map[string]string{"message": "member unbanned"})
}

func (a *App) ListCommunityAuditLog(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	logs, err := a.Repo.ListCommunityAuditLog(r.Context(), communityID, intQueryDefault(r, "limit", 50))
	if err != nil {
		internalError(w, "failed to load community audit")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": logs})
}

func (a *App) JoinCommunityByCode(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		Code        string `json:"code"`
		CommunityID string `json:"community_id"`
		Message     string `json:"message"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid request")
		return
	}
	lookupValue := strings.TrimSpace(body.CommunityID)
	if lookupValue == "" {
		lookupValue = strings.TrimSpace(body.Code)
	}
	if lookupValue == "" {
		badRequest(w, "community id or code is required")
		return
	}
	community, err := a.Repo.GetCommunityByID(r.Context(), uuidFromCode(lookupValue))
	if err != nil || community == nil {
		community, err = a.Repo.GetCommunityByCode(r.Context(), lookupValue)
		if err != nil {
			notFound(w, "community not found")
			return
		}
	}
	if community.IsPublic {
		if err := a.Repo.AddCommunityMember(r.Context(), community.ID, userID, "user"); err != nil {
			internalError(w, "failed to join community")
			return
		}
		writeJSON(w, http.StatusOK, map[string]string{"message": "joined community"})
		return
	}
	jr, err := a.Repo.CreateJoinRequest(r.Context(), community.ID, userID, body.Code, body.Message)
	if err != nil {
		internalError(w, "failed to create join request")
		return
	}
	admins := a.communityAdminIDs(r, community.ID)
	a.Hub.PublishToMany(admins, "community:join_request", map[string]interface{}{"community_id": community.ID, "request_id": jr.ID})
	writeJSON(w, http.StatusAccepted, map[string]string{"message": "join request submitted"})
}

func (a *App) RequestJoinCommunity(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	var body struct {
		Message string `json:"message"`
	}
	_ = parseJSON(r, &body)
	jr, err := a.Repo.CreateJoinRequest(r.Context(), communityID, userID, "", body.Message)
	if err != nil {
		internalError(w, "failed to create join request")
		return
	}
	admins := a.communityAdminIDs(r, communityID)
	a.Hub.PublishToMany(admins, "community:join_request", map[string]interface{}{"community_id": communityID, "request_id": jr.ID})
	writeJSON(w, http.StatusAccepted, map[string]string{"message": "join request submitted"})
}

func (a *App) ListJoinRequests(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, userID)
	if err != nil || (role != "admin" && role != "admin_sec" && role != "owner") {
		forbidden(w, "admin access required")
		return
	}
	requests, err := a.Repo.ListPendingJoinRequests(r.Context(), communityID)
	if err != nil {
		internalError(w, "failed to load join requests")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": requests})
}

func (a *App) ReviewJoinRequest(w http.ResponseWriter, r *http.Request) {
	reviewerID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, reviewerID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	requestID, err := parseUUIDParam(r, "req_id")
	if err != nil {
		badRequest(w, "invalid request id")
		return
	}
	var body struct {
		Action string `json:"action"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid request")
		return
	}
	status := "rejected"
	if body.Action == "approve" {
		status = "approved"
	}
	jr, err := a.Repo.UpdateJoinRequestStatus(r.Context(), requestID, reviewerID, status)
	if err != nil {
		internalError(w, "failed to update request")
		return
	}
	if status == "approved" {
		_ = a.Repo.AddCommunityMember(r.Context(), communityID, jr.UserID, "user")
		a.Hub.PublishToUser(jr.UserID.String(), "community:join_approved", map[string]interface{}{"community_id": communityID})
		_, _ = a.CreateNotificationForUser(r.Context(), jr.UserID, "join_request", map[string]interface{}{"community_id": communityID, "status": "approved"})
	}
	writeJSON(w, http.StatusOK, jr)
}

func (a *App) GenerateCommunityInvite(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, userID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"invite_code": communityID.String(),
		"invite_url":  fmt.Sprintf("%s/join?code=%s", r.Host, communityID.String()),
	})
}

func (a *App) GetCommunityMessages(w http.ResponseWriter, r *http.Request) {
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	cursor := r.URL.Query().Get("cursor")
	limit := intQueryDefault(r, "limit", 50)
	messages, next, hasMore, err := a.Repo.ListCommunityMessages(r.Context(), communityID, cursor, limit)
	if err != nil {
		internalError(w, "failed to fetch messages")
		return
	}
	writeJSON(w, http.StatusOK, paginatedResponse{Data: messages, NextCursor: next, HasMore: hasMore})
}

func (a *App) PostCommunityMessage(w http.ResponseWriter, r *http.Request) {
	senderID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	ok, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, senderID)
	if err != nil || !ok {
		forbidden(w, "not a member")
		return
	}
	if role == "viewer" {
		forbidden(w, "viewer cannot post messages")
		return
	}
	var body struct {
		Content string `json:"content"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Content) == "" {
		badRequest(w, "content is required")
		return
	}
	msg, err := a.Repo.CreateCommunityMessage(r.Context(), communityID, senderID, body.Content)
	if err != nil {
		internalError(w, "failed to post message")
		return
	}
	members, _ := a.Repo.ListCommunityMembers(r.Context(), communityID)
	targets := make([]string, 0, len(members))
	for _, m := range members {
		targets = append(targets, m.UserID.String())
	}
	a.Hub.PublishToMany(targets, "community:message", map[string]interface{}{"community_id": communityID, "message": msg})
	writeJSON(w, http.StatusCreated, msg)
}

func (a *App) CreateDepartment(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Name    string `json:"name"`
		Country string `json:"country"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Name) == "" {
		badRequest(w, "name is required")
		return
	}
	dept, err := a.Repo.CreateDepartment(r.Context(), communityID, body.Name, body.Country)
	if err != nil {
		internalError(w, "failed to create department")
		return
	}
	writeJSON(w, http.StatusCreated, dept)
}

func (a *App) UpdateDepartment(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	deptID, err := parseUUIDParam(r, "dept_id")
	if err != nil {
		badRequest(w, "invalid department id")
		return
	}
	var body struct {
		Name    string `json:"name"`
		Country string `json:"country"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	dept, err := a.Repo.UpdateDepartment(r.Context(), deptID, body.Name, body.Country)
	if err != nil {
		internalError(w, "failed to update department")
		return
	}
	writeJSON(w, http.StatusOK, dept)
}

func (a *App) DeleteDepartment(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	deptID, err := parseUUIDParam(r, "dept_id")
	if err != nil {
		badRequest(w, "invalid department id")
		return
	}
	if err := a.Repo.DeleteDepartment(r.Context(), deptID); err != nil {
		internalError(w, "failed to delete department")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "department deleted"})
}

func (a *App) AddCommunityMemberDirect(w http.ResponseWriter, r *http.Request) {
	actorID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	_, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || (role != "owner" && role != "admin" && role != "admin_sec") {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Email string `json:"email"`
		Role  string `json:"role"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Email) == "" {
		badRequest(w, "email is required")
		return
	}
	if strings.TrimSpace(body.Role) == "" {
		body.Role = "user"
	}
	user, err := a.Repo.GetUserByEmail(r.Context(), strings.ToLower(strings.TrimSpace(body.Email)))
	if err != nil {
		notFound(w, "user not found")
		return
	}
	if err := a.Repo.AddCommunityMember(r.Context(), communityID, user.ID, body.Role); err != nil {
		internalError(w, "failed to add member")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "member_added_direct", &user.ID, map[string]interface{}{"email": body.Email, "role": body.Role})
	a.Hub.PublishToUser(user.ID.String(), "community:added", map[string]interface{}{"community_id": communityID})
	writeJSON(w, http.StatusCreated, map[string]string{"message": "member added"})
}

func (a *App) communityAdminIDs(r *http.Request, communityID uuid.UUID) []string {
	members, err := a.Repo.ListCommunityMembers(r.Context(), communityID)
	if err != nil {
		return nil
	}
	ids := []string{}
	for _, m := range members {
		if m.Role == "owner" || m.Role == "admin" || m.Role == "admin_sec" {
			ids = append(ids, m.UserID.String())
		}
	}
	return ids
}

func generateCommunityCode(length int) (string, error) {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	if length <= 0 {
		length = 8
	}
	code := make([]byte, length)
	for i := range code {
		v, err := generateSessionPassword(1)
		if err != nil {
			return "", err
		}
		code[i] = v[0]
		_ = chars
	}
	if len(code) >= 8 {
		return string(code[:4]) + "-" + string(code[4:8]), nil
	}
	return string(code), nil
}

func uuidFromCode(raw string) uuid.UUID {
	parsed, err := uuid.Parse(strings.TrimSpace(raw))
	if err != nil {
		return uuid.Nil
	}
	return parsed
}
