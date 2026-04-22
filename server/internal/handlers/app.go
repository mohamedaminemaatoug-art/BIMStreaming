package handlers

import (
	"fmt"
	"net/http"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/email"
	"bimstreaming/server/internal/geoip"
	"bimstreaming/server/internal/middleware"
	"bimstreaming/server/internal/push"
	"bimstreaming/server/internal/repository"
	"bimstreaming/server/internal/storage"
	wshub "bimstreaming/server/internal/ws"

	"github.com/go-chi/chi/v5"
)

type App struct {
	Repo          *repository.Repository
	Tokens        *auth.TokenManager
	Email         *email.Sender
	GeoIP         *geoip.Client
	Avatar        *storage.AvatarService
	Attachments   *storage.AttachmentService
	Hub           *wshub.Hub
	Push          *push.Dispatcher
	AppBaseURL    string
	EncryptionKey []byte
}

func New(repo *repository.Repository, tokens *auth.TokenManager, emailSender *email.Sender, geo *geoip.Client, avatar *storage.AvatarService, attachments *storage.AttachmentService, hub *wshub.Hub, pushDispatcher *push.Dispatcher, appBaseURL string, encryptionKey string) (*App, error) {
	encKey := []byte(encryptionKey)
	if len(encKey) != 32 {
		return nil, fmt.Errorf("ENCRYPTION_KEY must be exactly 32 characters")
	}
	return &App{Repo: repo, Tokens: tokens, Email: emailSender, GeoIP: geo, Avatar: avatar, Attachments: attachments, Hub: hub, Push: pushDispatcher, AppBaseURL: appBaseURL, EncryptionKey: encKey}, nil
}

func (a *App) Mount(r chi.Router, authMW func(http.Handler) http.Handler, rateLimitMW func(http.Handler) http.Handler, planMW *middleware.PlanEnforcer) {
	r.Route("/api/v1", func(api chi.Router) {
		api.With(rateLimitMW).Route("/auth", func(ar chi.Router) {
			ar.Post("/register", a.Register)
			ar.Post("/verify-email", a.VerifyEmail)
			ar.Post("/resend-verification", a.ResendVerification)
			ar.Post("/login", a.Login)
			ar.Post("/2fa/challenge", a.TwoFactorChallenge)
			ar.Post("/2fa/setup", a.TwoFactorSetup)
			ar.Post("/2fa/verify", a.TwoFactorVerify)
			ar.Post("/2fa/disable", a.TwoFactorDisable)
			ar.Post("/2fa/backup", a.TwoFactorBackup)
			ar.Post("/refresh", a.Refresh)
			ar.Post("/logout", a.Logout)
			ar.Post("/forgot-password", a.ForgotPassword)
			ar.Post("/verify-reset-code", a.VerifyResetCode)
			ar.Post("/reset-password", a.ResetPassword)
			ar.Post("/change-password", a.ChangePassword)
		})

		api.Group(func(pr chi.Router) {
			pr.Use(authMW)
			pr.Use(middleware.Audit(a.Repo))
			pr.Post("/push/register", a.RegisterPushToken)
			pr.Delete("/push/unregister", a.UnregisterPushToken)
			pr.Get("/security/login-history", a.GetLoginHistory)
			pr.Get("/security/trusted-devices", a.GetTrustedDevices)
			pr.Delete("/security/trusted-devices/{id}", a.RevokeTrustedDevice)
			pr.Post("/security/revoke-all-sessions", a.RevokeAllSessions)
			pr.Get("/admin/audit", a.GetAuditLogs)
			pr.Get("/admin/users", a.AdminListUsers)
			pr.Get("/admin/users/{id}", a.AdminGetUser)
			pr.Post("/admin/users/{id}/ban", a.AdminBanUser)
			pr.Post("/admin/users/{id}/unban", a.AdminUnbanUser)
			pr.Post("/admin/users/{id}/verify", a.AdminVerifyUser)
			pr.Get("/admin/communities", a.AdminListCommunities)
			pr.Get("/admin/sessions", a.AdminListSessions)
			pr.Get("/admin/sessions/active", a.AdminListActiveSessions)
			pr.Get("/admin/stats", a.AdminGetStats)
			pr.Get("/users/me", a.GetMe)
			pr.Patch("/users/me", a.UpdateMe)
			pr.Patch("/users/me/notifications", a.UpdateMyNotifications)
			pr.Get("/users/me/export", a.QueueMyDataExport)
			pr.Post("/users/me/delete", a.RequestMyAccountDeletion)
			pr.Get("/users/me/status", a.GetMyStatus)
			pr.Patch("/users/me/status", a.UpdateMyStatus)
			pr.Post("/users/me/avatar", a.UploadAvatar)
			pr.Get("/users/search", a.SearchUsers)
			pr.Get("/users/{id}", a.GetUserProfile)
			pr.Get("/users/{id}/status", a.GetUserStatus)
			pr.Get("/subscriptions/me", a.GetMySubscription)

			pr.Get("/friends", a.ListFriends)
			pr.Get("/friends/requests", a.ListFriendRequests)
			pr.Get("/friends/blocked", a.ListBlockedUsers)
			pr.Post("/friends/request/{user_id}", a.SendFriendRequest)
			pr.Patch("/friends/request/{id}", a.ResolveFriendRequest)
			pr.Delete("/friends/{user_id}", a.DeleteFriend)
			pr.Post("/friends/block/{user_id}", a.BlockUser)

			pr.Get("/dm", a.ListConversations)
			pr.Get("/dm/{user_id}", a.GetDMHistory)
			pr.Post("/dm/{user_id}", a.SendDM)
			pr.Patch("/dm/{user_id}/read", a.MarkDMRead)

			if planMW != nil {
				pr.With(planMW.RequireMaxCommunities()).Post("/communities", a.CreateCommunity)
			} else {
				pr.Post("/communities", a.CreateCommunity)
			}
			pr.Get("/communities", a.ListCommunities)
			pr.Get("/communities/discover", a.DiscoverCommunities)
			pr.Post("/communities/join", a.JoinCommunityByCode)
			pr.Get("/communities/{id}", a.GetCommunity)
			pr.Patch("/communities/{id}", a.UpdateCommunity)
			pr.Delete("/communities/{id}", a.DeleteCommunity)
			pr.Get("/communities/{id}/announcements", a.ListCommunityAnnouncements)
			pr.Post("/communities/{id}/announcements", a.CreateCommunityAnnouncement)
			pr.Patch("/communities/{id}/announcements/{announcement_id}", a.UpdateCommunityAnnouncement)
			pr.Delete("/communities/{id}/announcements/{announcement_id}", a.DeleteCommunityAnnouncement)
			pr.Get("/communities/{id}/members", a.ListCommunityMembers)
			pr.Patch("/communities/{id}/members/{user_id}", a.UpdateCommunityMember)
			pr.Delete("/communities/{id}/members/{user_id}", a.RemoveCommunityMember)
			pr.Post("/communities/{id}/members/{user_id}/ban", a.BanCommunityMember)
			pr.Delete("/communities/{id}/members/{user_id}/ban", a.UnbanCommunityMember)
			pr.Post("/communities/{id}/request-join", a.RequestJoinCommunity)
			pr.Get("/communities/{id}/join-requests", a.ListJoinRequests)
			pr.Patch("/communities/{id}/join-requests/{req_id}", a.ReviewJoinRequest)
			pr.Post("/communities/{id}/invite", a.GenerateCommunityInvite)
			pr.Get("/communities/{id}/audit", a.ListCommunityAuditLog)
			pr.Get("/communities/{id}/messages", a.GetCommunityMessages)
			pr.Post("/communities/{id}/messages", a.PostCommunityMessage)
			pr.Patch("/communities/{id}/messages/{message_id}", a.UpdateCommunityMessage)
			pr.Delete("/communities/{id}/messages/{message_id}", a.DeleteCommunityMessage)
			pr.Get("/communities/{id}/messages/{message_id}/reactions", a.ListCommunityMessageReactions)
			pr.Post("/communities/{id}/messages/{message_id}/reactions", a.AddCommunityMessageReaction)
			pr.Delete("/communities/{id}/messages/{message_id}/reactions", a.RemoveCommunityMessageReaction)
			pr.Get("/communities/{id}/messages/{message_id}/attachments", a.ListCommunityMessageAttachments)
			pr.Post("/communities/{id}/messages/{message_id}/attachments", a.UploadCommunityMessageAttachment)

			pr.Post("/communities/{id}/departments", a.CreateDepartment)
			pr.Patch("/communities/{id}/departments/{dept_id}", a.UpdateDepartment)
			pr.Delete("/communities/{id}/departments/{dept_id}", a.DeleteDepartment)

			pr.Post("/remote/invite/{user_id}", a.CreateRemoteInvite)
			pr.Patch("/remote/invite/{id}", a.ResolveRemoteInvite)
			if planMW != nil {
				pr.With(planMW.RequireMaxConcurrentSessions()).Post("/remote/sessions", a.CreateRemoteSession)
				pr.With(planMW.RequireFeature("unattended_access")).Post("/remote/unattended-access", a.CreateUnattendedAccess)
			} else {
				pr.Post("/remote/sessions", a.CreateRemoteSession)
				pr.Post("/remote/unattended-access", a.CreateUnattendedAccess)
			}
			pr.Get("/remote/sessions/{id}", a.GetRemoteSession)
			pr.Patch("/remote/sessions/{id}/permissions", a.UpdateRemoteSessionPermissions)
			pr.Patch("/remote/sessions/{id}/quality", a.UpdateRemoteSessionQuality)
			pr.Patch("/remote/sessions/{id}/stats", a.UpdateRemoteSessionStats)
			pr.Post("/remote/sessions/{id}/end", a.EndRemoteSession)
			pr.Get("/remote/unattended-access", a.ListUnattendedAccess)
			pr.Delete("/remote/unattended-access/{id}", a.DeleteUnattendedAccess)
			pr.Get("/remote/history", a.GetRemoteHistory)

			pr.Get("/notifications", a.GetNotifications)
			pr.Post("/notifications", a.CreateNotification)
			pr.Patch("/notifications/read", a.MarkAllNotificationsRead)
			pr.Patch("/notifications/{id}/read", a.MarkNotificationRead)
		})
	})

	r.Get("/media/avatars/{filename}", a.ServeAvatar)
	r.Get("/media/attachments/{filename}", a.ServeAttachment)
	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
}
