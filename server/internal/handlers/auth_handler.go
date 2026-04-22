package handlers

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strings"
	"time"

	"bimstreaming/server/internal/auth"
	"bimstreaming/server/internal/geoip"
	"bimstreaming/server/internal/models"

	"github.com/google/uuid"
)

type registerRequest struct {
	Username        string `json:"username"`
	FullName        string `json:"full_name"`
	Email           string `json:"email"`
	Phone           string `json:"phone"`
	Password        string `json:"password"`
	ConfirmPassword string `json:"confirm_password"`
}

type verifyRequest struct {
	UserID string `json:"user_id"`
	Code   string `json:"code"`
}

type loginRequest struct {
	Identifier        string `json:"identifier"`
	Password          string `json:"password"`
	DeviceFingerprint string `json:"device_fingerprint"`
	DeviceLabel       string `json:"device_label"`
}

type twoFactorChallengeRequest struct {
	TempToken  string `json:"temp_token"`
	Code       string `json:"code"`
	BackupCode string `json:"backup_code"`
}

type twoFactorDisableRequest struct {
	Password string `json:"password"`
}

type twoFactorVerifyRequest struct {
	Code string `json:"code"`
}

func (a *App) Register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := parseJSON(r, &req); err != nil {
		badRequest(w, "invalid request body")
		return
	}
	if strings.TrimSpace(req.Username) == "" || strings.TrimSpace(req.Email) == "" {
		badRequest(w, "username and email are required")
		return
	}
	if req.Password != req.ConfirmPassword {
		badRequest(w, "password confirmation mismatch")
		return
	}
	if !auth.ValidateEmail(req.Email) {
		badRequest(w, "invalid email")
		return
	}
	if err := auth.ValidatePasswordStrength(req.Password); err != nil {
		badRequest(w, err.Error())
		return
	}
	exists, err := a.Repo.UsernameOrEmailExists(r.Context(), req.Username, req.Email)
	if err != nil {
		internalError(w, "failed to validate user uniqueness")
		return
	}
	if exists {
		badRequest(w, "username or email already in use")
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		internalError(w, "failed to hash password")
		return
	}
	userID := uuid.New()
	displayName := strings.TrimSpace(req.FullName)
	if displayName == "" {
		displayName = strings.TrimSpace(req.Username)
	}
	deviceID, err := buildDeviceID(req.Email, userID.String())
	if err != nil {
		internalError(w, "failed to build device id")
		return
	}
	user := &models.User{
		ID:           userID,
		Username:     req.Username,
		DisplayName:  nullString(displayName),
		Email:        req.Email,
		Phone:        nullString(req.Phone),
		PasswordHash: hash,
		DeviceID:     deviceID,
		IsVerified:   true,
	}
	if err := a.Repo.CreateUser(r.Context(), user); err != nil {
		internalError(w, "failed to create user")
		return
	}
	if err := a.Repo.MarkUserVerified(r.Context(), user.ID); err != nil {
		internalError(w, "failed to verify user")
		return
	}
	sessionPassword, err := generateSessionPassword(6)
	if err != nil {
		internalError(w, "failed to generate session password")
		return
	}
	deviceSession, err := a.Repo.UpsertDeviceSession(r.Context(), user.ID, user.DeviceID, sessionPassword, "")
	if err != nil {
		internalError(w, "failed to create device session")
		return
	}
	if a.Email != nil {
		if err := a.Email.SendWelcome(user.Email); err != nil {
			log.Printf("email send failed: type=welcome to=%s err=%v", user.Email, err)
		}
	}
	go func(email string, uid uuid.UUID) {
		if a.Avatar.HasGravatar(email) {
			_ = a.Repo.UpdateUserAvatar(r.Context(), uid, a.Avatar.GravatarURL(email))
		}
	}(user.Email, user.ID)
	a.respondAuthTokens(w, user, deviceSession, "")
}

func (a *App) VerifyEmail(w http.ResponseWriter, r *http.Request) {
	var req verifyRequest
	if err := parseJSON(r, &req); err != nil {
		badRequest(w, "invalid request body")
		return
	}
	if !auth.ValidateVerificationCode(req.Code) {
		badRequest(w, "invalid verification code")
		return
	}
	userID, err := uuid.Parse(req.UserID)
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	verification, err := a.Repo.GetLatestEmailVerification(r.Context(), userID, req.Code)
	if err != nil {
		unauthorized(w, "invalid verification code")
		return
	}
	if verification.UsedAt.Valid || time.Now().UTC().After(verification.ExpiresAt) {
		unauthorized(w, "verification code expired")
		return
	}
	if err := a.Repo.MarkEmailVerificationUsed(r.Context(), verification.ID); err != nil {
		internalError(w, "failed to mark verification")
		return
	}
	if err := a.Repo.MarkUserVerified(r.Context(), userID); err != nil {
		internalError(w, "failed to verify user")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		internalError(w, "failed to load user")
		return
	}
	if a.Email != nil {
		if err := a.Email.SendWelcome(user.Email); err != nil {
			log.Printf("email send failed: type=welcome to=%s err=%v", user.Email, err)
		}
	}
	sessionPassword, err := generateSessionPassword(6)
	if err != nil {
		internalError(w, "failed to build session password")
		return
	}
	deviceSession, err := a.Repo.UpsertDeviceSession(r.Context(), user.ID, user.DeviceID, sessionPassword, "")
	if err != nil {
		internalError(w, "failed to create device session")
		return
	}
	a.respondAuthTokens(w, user, deviceSession, "")
}

func (a *App) ResendVerification(w http.ResponseWriter, r *http.Request) {
	var body struct {
		UserID string `json:"user_id"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid request")
		return
	}
	userID, err := uuid.Parse(body.UserID)
	if err != nil {
		badRequest(w, "invalid user id")
		return
	}
	allowed, err := a.Repo.CanResendVerification(r.Context(), userID, time.Minute)
	if err != nil {
		internalError(w, "failed to check resend rate")
		return
	}
	if !allowed {
		writeJSON(w, http.StatusTooManyRequests, map[string]string{"error": "please wait before requesting another code"})
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	code, err := generateVerificationCode()
	if err != nil {
		internalError(w, "failed to generate code")
		return
	}
	if err := a.Repo.CreateEmailVerification(r.Context(), userID, code, time.Now().UTC().Add(10*time.Minute)); err != nil {
		internalError(w, "failed to create verification")
		return
	}
	if a.Email != nil {
		if err := a.Email.SendVerificationCode(user.Email, code); err != nil {
			log.Printf("email send failed: type=verify_email to=%s err=%v", user.Email, err)
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "verification code resent"})
}

func (a *App) Login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := parseJSON(r, &req); err != nil {
		badRequest(w, "invalid request body")
		return
	}
	kind, normalized := auth.NormalizeIdentifier(req.Identifier)
	user, err := a.Repo.GetUserByIdentifier(r.Context(), kind, normalized)
	if err != nil {
		a.recordLoginAttempt(r.Context(), r, nil, req, "failed", "invalid credentials", geoip.GeoResult{})
		unauthorized(w, "invalid credentials")
		return
	}
	if user.IsBanned {
		a.recordLoginAttempt(r.Context(), r, user, req, "blocked", "account banned", geoip.GeoResult{})
		forbidden(w, "account banned")
		return
	}
	if user.LockedUntil.Valid && time.Now().UTC().Before(user.LockedUntil.Time) {
		a.recordLoginAttempt(r.Context(), r, user, req, "blocked", "account locked", geoip.GeoResult{})
		unauthorized(w, "account temporarily locked")
		return
	}
	if err := auth.VerifyPassword(user.PasswordHash, req.Password); err != nil {
		a.handleFailedLogin(r.Context(), r, user, req, "invalid credentials")
		unauthorized(w, "invalid credentials")
		return
	}
	if !user.IsVerified {
		a.recordLoginAttempt(r.Context(), r, user, req, "failed", "email not verified", geoip.GeoResult{})
		unauthorized(w, "email not verified")
		return
	}
	geoResult := geoip.GeoResult{}
	if a.GeoIP != nil {
		geoResult, _ = a.GeoIP.LookupIP(r.Context(), clientIP(r))
	}
	sessionPassword, err := generateSessionPassword(6)
	if err != nil {
		internalError(w, "failed to generate session password")
		return
	}
	deviceSession, err := a.Repo.UpsertDeviceSession(r.Context(), user.ID, user.DeviceID, sessionPassword, req.DeviceLabel)
	if err != nil {
		internalError(w, "failed to update device session")
		return
	}
	if user.TwoFactorEnabled {
		tempToken, err := a.Tokens.GeneratePurposeToken(user.ID.String(), "2fa", 5*time.Minute)
		if err != nil {
			internalError(w, "failed to issue 2fa token")
			return
		}
		a.recordLoginAttempt(r.Context(), r, user, req, "success", "2fa challenge issued", geoResult)
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"requires_2fa": true,
			"temp_token":   tempToken,
		})
		return
	}
	a.recordLoginAttempt(r.Context(), r, user, req, "success", "login completed", geoResult)
	a.respondAuthTokens(w, user, deviceSession, req.DeviceFingerprint)
}

func (a *App) ChangePassword(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}

	var body struct {
		CurrentPassword string `json:"current_password"`
		NewPassword     string `json:"new_password"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid body")
		return
	}
	if strings.TrimSpace(body.CurrentPassword) == "" || strings.TrimSpace(body.NewPassword) == "" {
		badRequest(w, "current_password and new_password are required")
		return
	}

	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	if err := auth.VerifyPassword(user.PasswordHash, body.CurrentPassword); err != nil {
		unauthorized(w, "current password is incorrect")
		return
	}
	if err := auth.ValidatePasswordStrength(body.NewPassword); err != nil {
		badRequest(w, err.Error())
		return
	}
	newHash, err := auth.HashPassword(body.NewPassword)
	if err != nil {
		internalError(w, "failed to hash new password")
		return
	}
	if err := a.Repo.UpdateUserPassword(r.Context(), userID, newHash); err != nil {
		internalError(w, "failed to update password")
		return
	}
	_ = a.Repo.RevokeAllRefreshTokensForUser(r.Context(), userID)

	writeJSON(w, http.StatusOK, map[string]string{"message": "password updated"})
}

func (a *App) TwoFactorChallenge(w http.ResponseWriter, r *http.Request) {
	var req twoFactorChallengeRequest
	if err := parseJSON(r, &req); err != nil {
		badRequest(w, "invalid request")
		return
	}
	claims, err := a.Tokens.ParsePurposeToken(req.TempToken, "2fa")
	if err != nil {
		unauthorized(w, "invalid temporary token")
		return
	}
	userID, err := uuid.Parse(claims.Subject)
	if err != nil {
		unauthorized(w, "invalid temporary token")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil || !user.TwoFactorEnabled || !user.TwoFactorSecret.Valid {
		unauthorized(w, "2fa not enabled")
		return
	}
	secret, err := auth.DecryptAESGCM(user.TwoFactorSecret.String, a.EncryptionKey)
	if err != nil {
		internalError(w, "failed to decrypt 2fa secret")
		return
	}
	verified := false
	if strings.TrimSpace(req.Code) != "" {
		verified = auth.VerifyTOTPCode(string(secret), req.Code, time.Now().UTC(), 1)
	}
	if !verified && strings.TrimSpace(req.BackupCode) != "" {
		codes, err := a.Repo.ListUnusedTOTPBackupCodes(r.Context(), userID)
		if err == nil {
			for _, backup := range codes {
				if auth.VerifyPassword(backup.CodeHash, req.BackupCode) == nil {
					_ = a.Repo.MarkTOTPBackupCodeUsed(r.Context(), backup.ID)
					verified = true
					break
				}
			}
		}
	}
	if !verified {
		a.handleFailedLogin(r.Context(), r, user, loginRequest{}, "invalid 2fa code")
		unauthorized(w, "invalid 2fa code")
		return
	}
	deviceSession, err := a.Repo.GetDeviceSessionByUserID(r.Context(), userID)
	if err != nil {
		sessionPassword, genErr := generateSessionPassword(6)
		if genErr != nil {
			internalError(w, "failed to generate session password")
			return
		}
		deviceSession, err = a.Repo.UpsertDeviceSession(r.Context(), user.ID, user.DeviceID, sessionPassword, "")
		if err != nil {
			internalError(w, "failed to create device session")
			return
		}
	}
	a.respondAuthTokens(w, user, deviceSession, "")
}

func (a *App) TwoFactorSetup(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	secret, err := auth.GenerateTOTPSecret()
	if err != nil {
		internalError(w, "failed to generate totp secret")
		return
	}
	encrypted, err := auth.EncryptAESGCM([]byte(secret), a.EncryptionKey)
	if err != nil {
		internalError(w, "failed to encrypt totp secret")
		return
	}
	if err := a.Repo.SetTwoFactorSecret(r.Context(), user.ID, encrypted); err != nil {
		internalError(w, "failed to store totp secret")
		return
	}
	uri := auth.BuildTOTPURI("bim streaming", user.Username, secret)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"secret":       secret,
		"qr_code_uri":  uri,
		"manual_code":  secret,
		"issuer":       "bim streaming",
		"account_name": user.Username,
	})
}

func (a *App) TwoFactorVerify(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var req twoFactorVerifyRequest
	if err := parseJSON(r, &req); err != nil {
		badRequest(w, "invalid request")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil || !user.TwoFactorSecret.Valid {
		badRequest(w, "2fa setup not initialized")
		return
	}
	secret, err := auth.DecryptAESGCM(user.TwoFactorSecret.String, a.EncryptionKey)
	if err != nil {
		internalError(w, "failed to decrypt totp secret")
		return
	}
	if !auth.VerifyTOTPCode(string(secret), req.Code, time.Now().UTC(), 1) {
		unauthorized(w, "invalid code")
		return
	}
	backupCodes := make([]string, 0, 10)
	backupHashes := make([]string, 0, 10)
	for i := 0; i < 10; i++ {
		code, err := auth.GenerateBackupCode()
		if err != nil {
			internalError(w, "failed to generate backup code")
			return
		}
		hash, err := auth.HashPassword(code)
		if err != nil {
			internalError(w, "failed to hash backup code")
			return
		}
		backupCodes = append(backupCodes, code)
		backupHashes = append(backupHashes, hash)
	}
	if err := a.Repo.EnableTwoFactor(r.Context(), userID); err != nil {
		internalError(w, "failed to enable 2fa")
		return
	}
	if err := a.Repo.ReplaceTOTPBackupCodes(r.Context(), userID, backupHashes); err != nil {
		internalError(w, "failed to store backup codes")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"message":      "2fa enabled",
		"backup_codes": backupCodes,
	})
}

func (a *App) TwoFactorDisable(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	var req twoFactorDisableRequest
	if err := parseJSON(r, &req); err != nil || strings.TrimSpace(req.Password) == "" {
		badRequest(w, "password is required")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil {
		notFound(w, "user not found")
		return
	}
	if err := auth.VerifyPassword(user.PasswordHash, req.Password); err != nil {
		unauthorized(w, "invalid password")
		return
	}
	if err := a.Repo.DisableTwoFactor(r.Context(), userID); err != nil {
		internalError(w, "failed to disable 2fa")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "2fa disabled"})
}

func (a *App) TwoFactorBackup(w http.ResponseWriter, r *http.Request) {
	userID, err := currentUserID(r)
	if err != nil {
		unauthorized(w, "unauthorized")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), userID)
	if err != nil || !user.TwoFactorEnabled {
		badRequest(w, "2fa must be enabled")
		return
	}
	backupCodes := make([]string, 0, 10)
	backupHashes := make([]string, 0, 10)
	for i := 0; i < 10; i++ {
		code, err := auth.GenerateBackupCode()
		if err != nil {
			internalError(w, "failed to generate backup code")
			return
		}
		hash, err := auth.HashPassword(code)
		if err != nil {
			internalError(w, "failed to hash backup code")
			return
		}
		backupCodes = append(backupCodes, code)
		backupHashes = append(backupHashes, hash)
	}
	if err := a.Repo.ReplaceTOTPBackupCodes(r.Context(), userID, backupHashes); err != nil {
		internalError(w, "failed to replace backup codes")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"backup_codes": backupCodes,
	})
}

func (a *App) Refresh(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.RefreshToken) == "" {
		badRequest(w, "refresh token is required")
		return
	}
	hash := auth.Sha256Hex(body.RefreshToken)
	stored, err := a.Repo.GetRefreshToken(r.Context(), hash)
	if err != nil || stored.RevokedAt.Valid || time.Now().UTC().After(stored.ExpiresAt) {
		unauthorized(w, "invalid refresh token")
		return
	}
	user, err := a.Repo.GetUserByID(r.Context(), stored.UserID)
	if err != nil {
		unauthorized(w, "invalid refresh token")
		return
	}
	accessToken, err := a.Tokens.GenerateAccessToken(user.ID.String(), user.DeviceID, "user", 15*time.Minute)
	if err != nil {
		internalError(w, "failed to issue access token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"access_token": accessToken})
}

func (a *App) Logout(w http.ResponseWriter, r *http.Request) {
	var body struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := parseJSON(r, &body); err != nil || strings.TrimSpace(body.RefreshToken) == "" {
		badRequest(w, "refresh token is required")
		return
	}
	if err := a.Repo.RevokeRefreshTokenByHash(r.Context(), auth.Sha256Hex(body.RefreshToken)); err != nil {
		internalError(w, "failed to revoke token")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "logged out"})
}

func (a *App) ForgotPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email string `json:"email"`
	}
	if err := parseJSON(r, &body); err != nil || !auth.ValidateEmail(body.Email) {
		badRequest(w, "valid email required")
		return
	}
	user, err := a.Repo.GetUserByEmail(r.Context(), body.Email)
	if err != nil {
		writeJSON(w, http.StatusOK, map[string]string{"message": "if account exists, reset code sent"})
		return
	}
	code, err := generateVerificationCode()
	if err != nil {
		internalError(w, "failed to generate reset code")
		return
	}
	hash := auth.Sha256Hex(code)
	if err := a.Repo.CreatePasswordReset(r.Context(), user.ID, hash, time.Now().UTC().Add(10*time.Minute)); err != nil {
		internalError(w, "failed to store reset code")
		return
	}
	if a.Email != nil {
		if err := a.Email.SendPasswordReset(user.Email, code); err != nil {
			log.Printf("email send failed: type=reset_password to=%s err=%v", user.Email, err)
		}
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "if account exists, reset code sent"})
}

func (a *App) VerifyResetCode(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email string `json:"email"`
		Code  string `json:"code"`
	}
	if err := parseJSON(r, &body); err != nil || !auth.ValidateEmail(body.Email) || strings.TrimSpace(body.Code) == "" {
		badRequest(w, "valid email and code required")
		return
	}
	user, err := a.Repo.GetUserByEmail(r.Context(), body.Email)
	if err != nil {
		badRequest(w, "invalid email or code")
		return
	}
	hash := auth.Sha256Hex(body.Code)
	reset, err := a.Repo.GetPasswordResetByHash(r.Context(), hash)
	if err != nil || reset.UserID != user.ID || reset.UsedAt.Valid || time.Now().UTC().After(reset.ExpiresAt) {
		badRequest(w, "invalid or expired code")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"message": "code verified"})
}

func (a *App) ResetPassword(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Email           string `json:"email"`
		Code            string `json:"code"`
		Password        string `json:"password"`
		ConfirmPassword string `json:"confirm_password"`
	}
	if err := parseJSON(r, &body); err != nil {
		badRequest(w, "invalid request")
		return
	}
	if body.Password != body.ConfirmPassword {
		badRequest(w, "password confirmation mismatch")
		return
	}
	if err := auth.ValidatePasswordStrength(body.Password); err != nil {
		badRequest(w, err.Error())
		return
	}
	if !auth.ValidateEmail(body.Email) || strings.TrimSpace(body.Code) == "" {
		badRequest(w, "valid email and code required")
		return
	}
	user, err := a.Repo.GetUserByEmail(r.Context(), body.Email)
	if err != nil {
		badRequest(w, "invalid email or code")
		return
	}
	hash := auth.Sha256Hex(body.Code)
	reset, err := a.Repo.GetPasswordResetByHash(r.Context(), hash)
	if err != nil || reset.UserID != user.ID || reset.UsedAt.Valid || time.Now().UTC().After(reset.ExpiresAt) {
		badRequest(w, "invalid or expired code")
		return
	}
	passwordHash, err := auth.HashPassword(body.Password)
	if err != nil {
		internalError(w, "failed to hash password")
		return
	}
	if err := a.Repo.UpdateUserPassword(r.Context(), user.ID, passwordHash); err != nil {
		internalError(w, "failed to update password")
		return
	}
	_ = a.Repo.MarkPasswordResetUsed(r.Context(), reset.ID)
	_ = a.Repo.RevokeAllRefreshTokensForUser(r.Context(), user.ID)
	writeJSON(w, http.StatusOK, map[string]string{"message": "password reset successful"})
}

func (a *App) respondAuthTokens(w http.ResponseWriter, user *models.User, ds *models.DeviceSession, deviceFingerprint string) {
	access, err := a.Tokens.GenerateAccessToken(user.ID.String(), user.DeviceID, "user", 15*time.Minute)
	if err != nil {
		internalError(w, "failed to issue access token")
		return
	}
	refresh, err := auth.GenerateOpaqueToken(32)
	if err != nil {
		internalError(w, "failed to issue refresh token")
		return
	}
	if err := a.Repo.CreateRefreshToken(context.Background(), user.ID, auth.Sha256Hex(refresh), deviceFingerprint, time.Now().UTC().Add(30*24*time.Hour)); err != nil {
		internalError(w, "failed to store refresh token")
		return
	}
	if err := a.Repo.SetOnlineStatus(context.Background(), user.ID, true); err == nil {
		user.IsOnline = true
	}
	phone := strings.TrimSpace(user.Phone.String)
	avatarURL := strings.TrimSpace(user.AvatarURL.String)
	displayName := strings.TrimSpace(user.DisplayName.String)
	if displayName == "" {
		displayName = user.Username
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"access_token":  access,
		"refresh_token": refresh,
		"user": map[string]interface{}{
			"id":           user.ID,
			"username":     user.Username,
			"display_name": displayName,
			"email":        user.Email,
			"phone":        phone,
			"avatar_url":   avatarURL,
			"device_id":    user.DeviceID,
			"is_verified":  user.IsVerified,
			"is_online":    user.IsOnline,
		},
		"device_session": ds,
	})
}

func (a *App) recordLoginAttempt(ctx context.Context, r *http.Request, user *models.User, req loginRequest, status, reason string, geoResult geoip.GeoResult) {
	shouldSendLoginAlert := false
	if status == "success" && user != nil && geoResult.Country != "" {
		hasCountry, err := a.Repo.HasSuccessfulLoginInCountry(ctx, user.ID, geoResult.Country)
		if err == nil && !hasCountry {
			shouldSendLoginAlert = true
		}
	}

	var userID uuid.UUID
	if user != nil {
		userID = user.ID
	}
	loginHistory := models.LoginHistory{
		ID:                uuid.New(),
		UserID:            userID,
		IPAddress:         clientIP(r),
		DeviceFingerprint: strings.TrimSpace(req.DeviceFingerprint),
		OS:                detectLoginOS(r.UserAgent()),
		AppVersion:        strings.TrimSpace(r.Header.Get("X-App-Version")),
		Status:            status,
		FailureReason:     nullString(reason),
	}
	if geoResult.Country != "" {
		loginHistory.Country = sql.NullString{String: geoResult.Country, Valid: true}
	}
	if geoResult.City != "" {
		loginHistory.City = sql.NullString{String: geoResult.City, Valid: true}
	}
	_ = a.Repo.InsertLoginHistory(ctx, loginHistory)
	if userID != uuid.Nil {
		_ = a.Repo.InsertAuditLog(ctx, models.AuditLog{
			ID:           uuid.New(),
			UserID:       uuid.NullUUID{UUID: userID, Valid: true},
			Action:       "login_" + status,
			ResourceType: "auth",
			ResourceID:   userID.String(),
			IPAddress:    clientIP(r),
			UserAgent:    r.UserAgent(),
		})
	}
	if shouldSendLoginAlert && a.Email != nil {
		go func(userID uuid.UUID, email string, result geoip.GeoResult) {
			if err := a.Email.SendLoginAlert(email, result.Country, result.City, time.Now().UTC().Format(time.RFC3339), strings.TrimSpace(req.DeviceLabel)); err != nil {
				log.Printf("email send failed: type=login_alert to=%s err=%v", email, err)
			}
		}(userID, user.Email, geoResult)
	}
}

func (a *App) handleFailedLogin(ctx context.Context, r *http.Request, user *models.User, req loginRequest, reason string) {
	if user == nil {
		return
	}
	a.recordLoginAttempt(ctx, r, user, req, "failed", reason, geoip.GeoResult{})
	count, err := a.Repo.IncrementFailedLoginCount(ctx, user.ID)
	if err != nil {
		return
	}
	if count >= 10 {
		_ = a.Repo.BanUser(ctx, user.ID, "too many failed logins")
		return
	}
	if count >= 5 {
		lockUntil := time.Now().UTC().Add(15 * time.Minute)
		_ = a.Repo.LockUserUntil(ctx, user.ID, lockUntil)
		if a.Email != nil {
			if err := a.Email.SendAccountLocked(user.Email); err != nil {
				log.Printf("email send failed: type=account_locked to=%s err=%v", user.Email, err)
			}
		}
	}
}

func detectLoginOS(userAgent string) string {
	userAgent = strings.ToLower(strings.TrimSpace(userAgent))
	switch {
	case strings.Contains(userAgent, "windows"):
		return "windows"
	case strings.Contains(userAgent, "mac os") || strings.Contains(userAgent, "macos") || strings.Contains(userAgent, "darwin"):
		return "macos"
	case strings.Contains(userAgent, "linux"):
		return "linux"
	case strings.Contains(userAgent, "android"):
		return "android"
	case strings.Contains(userAgent, "iphone") || strings.Contains(userAgent, "ios"):
		return "ios"
	default:
		return "unknown"
	}
}

func generateVerificationCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}

func generateSessionPassword(length int) (string, error) {
	const charset = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	if length <= 0 {
		length = 6
	}
	result := make([]byte, length)
	for i := range result {
		n, err := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		if err != nil {
			return "", err
		}
		result[i] = charset[n.Int64()]
	}
	return string(result), nil
}

func buildDeviceID(machineFingerprint, userID string) (string, error) {
	raw := auth.Sha256Hex(machineFingerprint + userID)
	if len(raw) < 18 {
		return "", fmt.Errorf("unexpected hash length")
	}
	digits := ""
	for _, ch := range raw {
		if ch >= '0' && ch <= '9' {
			digits += string(ch)
		}
		if len(digits) == 9 {
			break
		}
	}
	if len(digits) < 9 {
		decoded, err := hex.DecodeString(raw)
		if err != nil {
			return "", err
		}
		for _, b := range decoded {
			digits += fmt.Sprintf("%d", int(b)%10)
			if len(digits) == 9 {
				break
			}
		}
	}
	if len(digits) != 9 {
		return "", fmt.Errorf("failed to derive 9-digit device id")
	}
	return fmt.Sprintf("%s • %s • %s", digits[0:3], digits[3:6], digits[6:9]), nil
}

func nullString(v string) sql.NullString {
	v = strings.TrimSpace(v)
	if v == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: v, Valid: true}
}
