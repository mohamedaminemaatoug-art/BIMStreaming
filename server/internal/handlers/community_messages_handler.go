package handlers

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/go-chi/chi/v5"
)

func (a *App) UpdateCommunityMessage(w http.ResponseWriter, r *http.Request) {
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
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	msg, err := a.Repo.GetCommunityMessageByID(r.Context(), messageID)
	if err != nil || msg.CommunityID != communityID {
		notFound(w, "message not found")
		return
	}
	ok, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || !ok {
		forbidden(w, "not a member")
		return
	}
	if msg.SenderID != actorID && role != "owner" && role != "admin" && role != "admin_sec" {
		forbidden(w, "not allowed")
		return
	}
	var body struct {
		Content string `json:"content"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Content) == "" {
		badRequest(w, "content is required")
		return
	}
	updated, err := a.Repo.UpdateCommunityMessage(r.Context(), messageID, body.Content)
	if err != nil {
		internalError(w, "failed to update message")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "message_updated", nil, map[string]interface{}{"message_id": messageID})
	a.Hub.PublishToMany(a.communityAdminIDs(r, communityID), "community:message_updated", map[string]interface{}{"community_id": communityID, "message": updated})
	writeJSON(w, http.StatusOK, updated)
}

func (a *App) DeleteCommunityMessage(w http.ResponseWriter, r *http.Request) {
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
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	msg, err := a.Repo.GetCommunityMessageByID(r.Context(), messageID)
	if err != nil || msg.CommunityID != communityID {
		notFound(w, "message not found")
		return
	}
	ok, role, err := a.Repo.IsCommunityMember(r.Context(), communityID, actorID)
	if err != nil || !ok {
		forbidden(w, "not a member")
		return
	}
	if msg.SenderID != actorID && role != "owner" && role != "admin" && role != "admin_sec" {
		forbidden(w, "not allowed")
		return
	}
	if err := a.Repo.DeleteCommunityMessage(r.Context(), messageID); err != nil {
		internalError(w, "failed to delete message")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "message_deleted", nil, map[string]interface{}{"message_id": messageID})
	writeJSON(w, http.StatusOK, map[string]string{"message": "message deleted"})
}

func (a *App) AddCommunityMessageReaction(w http.ResponseWriter, r *http.Request) {
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
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	msg, err := a.Repo.GetCommunityMessageByID(r.Context(), messageID)
	if err != nil || msg.CommunityID != communityID {
		notFound(w, "message not found")
		return
	}
	var body struct {
		Emoji string `json:"emoji"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Emoji) == "" {
		badRequest(w, "emoji is required")
		return
	}
	if err := a.Repo.AddMessageReaction(r.Context(), messageID, "community", actorID, body.Emoji); err != nil {
		internalError(w, "failed to add reaction")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "message_reacted", nil, map[string]interface{}{"message_id": messageID, "emoji": body.Emoji})
	writeJSON(w, http.StatusOK, map[string]string{"message": "reaction added"})
}

func (a *App) RemoveCommunityMessageReaction(w http.ResponseWriter, r *http.Request) {
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
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	var body struct {
		Emoji string `json:"emoji"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.Emoji) == "" {
		badRequest(w, "emoji is required")
		return
	}
	if err := a.Repo.RemoveMessageReaction(r.Context(), messageID, "community", actorID, body.Emoji); err != nil {
		internalError(w, "failed to remove reaction")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, actorID, "message_reaction_removed", nil, map[string]interface{}{"message_id": messageID, "emoji": body.Emoji})
	writeJSON(w, http.StatusOK, map[string]string{"message": "reaction removed"})
}

func (a *App) ListCommunityMessageReactions(w http.ResponseWriter, r *http.Request) {
	_, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	reactions, err := a.Repo.ListMessageReactions(r.Context(), messageID, "community")
	if err != nil {
		internalError(w, "failed to load reactions")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": reactions})
}

func (a *App) UploadCommunityMessageAttachment(w http.ResponseWriter, r *http.Request) {
	uploaderID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	communityID, err := parseUUIDParam(r, "id")
	if err != nil {
		badRequest(w, "invalid community id")
		return
	}
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	msg, err := a.Repo.GetCommunityMessageByID(r.Context(), messageID)
	if err != nil || msg.CommunityID != communityID {
		notFound(w, "message not found")
		return
	}
	if err := r.ParseMultipartForm(20 << 20); err != nil {
		badRequest(w, "invalid multipart body")
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		badRequest(w, "file is required")
		return
	}
	defer file.Close()
	if a.Attachments == nil {
		internalError(w, "attachments service unavailable")
		return
	}
	_, publicURL, size, err := a.Attachments.SaveAttachment(file, header, uploaderID)
	if err != nil {
		badRequest(w, err.Error())
		return
	}
	att, err := a.Repo.AddMessageAttachment(r.Context(), messageID, "community", uploaderID, header.Filename, size, header.Header.Get("Content-Type"), publicURL, "")
	if err != nil {
		internalError(w, "failed to save attachment")
		return
	}
	_ = a.Repo.InsertCommunityAuditLog(r.Context(), communityID, uploaderID, "message_attachment_added", nil, map[string]interface{}{"message_id": messageID, "attachment_id": att.ID})
	writeJSON(w, http.StatusCreated, att)
}

func (a *App) ListCommunityMessageAttachments(w http.ResponseWriter, r *http.Request) {
	messageID, err := parseUUIDParam(r, "message_id")
	if err != nil {
		badRequest(w, "invalid message id")
		return
	}
	attachments, err := a.Repo.ListMessageAttachments(r.Context(), messageID, "community")
	if err != nil {
		internalError(w, "failed to load attachments")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"data": attachments})
}

func (a *App) ServeAttachment(w http.ResponseWriter, r *http.Request) {
	filename := filepath.Base(chi.URLParam(r, "filename"))
	if filename == "" {
		notFound(w, "attachment not found")
		return
	}
	if a.Attachments == nil {
		notFound(w, "attachment not found")
		return
	}
	path := filepath.Join(a.Attachments.StoragePath(), filename)
	if _, err := os.Stat(path); err != nil {
		notFound(w, "attachment not found")
		return
	}
	http.ServeFile(w, r, path)
}
