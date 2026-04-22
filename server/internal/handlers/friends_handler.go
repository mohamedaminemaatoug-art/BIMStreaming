package handlers

import (
	"net/http"
	"strings"
	"time"

	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

func (a *App) ListFriends(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	friends, err := a.Repo.ListAcceptedFriends(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to list friends")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": friends})
}

func (a *App) ListFriendRequests(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	incoming, outgoing, err := a.Repo.GetFriendRequests(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to load requests")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"incoming": incoming, "outgoing": outgoing})
}

func (a *App) SendFriendRequest(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	targetID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid target user id")
		return
	}
	request, err := a.Repo.CreateFriendRequest(r.Context(), userID, targetID)
	if err != nil {
		msg := strings.ToLower(err.Error())
		switch {
		case strings.Contains(msg, "yourself"):
			badRequest(w, "cannot add yourself")
		case strings.Contains(msg, "already friends"):
			badRequest(w, "you are already friends")
		case strings.Contains(msg, "blocked"):
			badRequest(w, "friend request blocked")
		default:
			internalError(w, "failed to create friend request")
		}
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{ID: uuid.New(), UserID: uuid.NullUUID{UUID: userID, Valid: true}, Action: "friend_request_sent", ResourceType: "friendship", ResourceID: request.ID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	if request.Status == "accepted" {
		a.Hub.PublishToUser(targetID.String(), "friend:accepted", map[string]interface{}{"friendship_id": request.ID, "user_id": userID})
		a.Hub.PublishToUser(userID.String(), "friend:accepted", map[string]interface{}{"friendship_id": request.ID, "user_id": targetID})
		writeJSON(w, http.StatusOK, request)
		return
	}
	a.Hub.PublishToUser(targetID.String(), "friend:request", map[string]interface{}{"friendship_id": request.ID, "requester_id": userID})
	_, _ = a.CreateNotificationForUser(r.Context(), targetID, "friend_request", map[string]interface{}{"requester_id": userID, "at": time.Now().UTC()})
	writeJSON(w, http.StatusCreated, request)
}

func (a *App) ResolveFriendRequest(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	requestID, err := parseUUIDParam(r, "id")
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
	fr, err := a.Repo.GetFriendshipByID(r.Context(), requestID)
	if err != nil {
		notFound(w, "friend request not found")
		return
	}
	if fr.AddresseeID != userID {
		forbidden(w, "not allowed")
		return
	}
	status := "pending"
	if body.Action == "accept" {
		status = "accepted"
	} else if body.Action == "reject" {
		status = "blocked"
	} else {
		badRequest(w, "action must be accept or reject")
		return
	}
	updated, err := a.Repo.UpdateFriendshipStatus(r.Context(), fr.ID, status)
	if err != nil {
		internalError(w, "failed to update request")
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{ID: uuid.New(), UserID: uuid.NullUUID{UUID: userID, Valid: true}, Action: "friend_request_" + status, ResourceType: "friendship", ResourceID: updated.ID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	if status == "accepted" {
		a.Hub.PublishToUser(fr.RequesterID.String(), "friend:accepted", map[string]interface{}{"friendship_id": fr.ID, "user_id": userID})
	}
	writeJSON(w, http.StatusOK, updated)
}

func (a *App) DeleteFriend(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	otherID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	if err := a.Repo.DeleteFriendship(r.Context(), userID, otherID); err != nil {
		internalError(w, "failed to delete friendship")
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{ID: uuid.New(), UserID: uuid.NullUUID{UUID: userID, Valid: true}, Action: "friend_removed", ResourceType: "friendship", ResourceID: otherID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	writeJSON(w, http.StatusOK, map[string]string{"message": "friendship removed"})
}

func (a *App) BlockUser(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	otherID, err := parseUUIDParam(r, "user_id")
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	fr, err := a.Repo.CreateFriendRequest(r.Context(), userID, otherID)
	if err != nil {
		internalError(w, "failed to block user")
		return
	}
	_, err = a.Repo.UpdateFriendshipStatus(r.Context(), fr.ID, "blocked")
	if err != nil {
		internalError(w, "failed to block user")
		return
	}
	_ = a.Repo.InsertAuditLog(r.Context(), models.AuditLog{ID: uuid.New(), UserID: uuid.NullUUID{UUID: userID, Valid: true}, Action: "friend_blocked", ResourceType: "friendship", ResourceID: fr.ID.String(), IPAddress: clientIP(r), UserAgent: r.UserAgent()})
	writeJSON(w, http.StatusOK, map[string]string{"message": "user blocked"})
}

func (a *App) ListBlockedUsers(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	blocked, err := a.Repo.ListBlockedFriends(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to list blocked users")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": blocked})
}
