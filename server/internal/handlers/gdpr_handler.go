package handlers

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"github.com/google/uuid"
)

func (a *App) QueueMyDataExport(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	req, err := a.Repo.QueueDataExport(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to queue export")
		return
	}
	go a.completeDataExport(req.ID, userID)
	writeJSON(w, http.StatusAccepted, map[string]interface{}{"message": "data export queued", "request": req})
}

func (a *App) completeDataExport(exportID uuid.UUID, userID uuid.UUID) {
	ctx := context.Background()
	downloadURL := fmt.Sprintf("%s/exports/%s.zip", a.AppBaseURL, exportID.String())
	ready, err := a.Repo.MarkDataExportReady(ctx, exportID, downloadURL)
	if err != nil || ready == nil {
		return
	}
	user, err := a.Repo.GetUserByID(ctx, userID)
	if err == nil {
		_ = a.Email.SendDataExportReady(user.Email, downloadURL)
	}
}

func (a *App) RequestMyAccountDeletion(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	_ = parseJSON(r, &body)
	scheduled := time.Now().UTC().Add(30 * 24 * time.Hour)
	req, err := a.Repo.RequestAccountDeletion(r.Context(), userID, scheduled, body.Reason)
	if err != nil {
		internalError(w, "failed to schedule account deletion")
		return
	}
	if user, userErr := a.Repo.GetUserByID(r.Context(), userID); userErr == nil {
		_ = a.Email.SendAccountDeletionNotice(user.Email, scheduled.Format("2006-01-02"))
	}
	writeJSON(w, http.StatusAccepted, map[string]interface{}{"message": "account deletion scheduled", "request": req})
}
