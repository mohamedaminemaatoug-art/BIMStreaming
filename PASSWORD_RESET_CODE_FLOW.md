# Password Reset Code Flow - Implementation Summary

## Overview
Successfully migrated password reset flow from token/link-based to 6-digit verification code system. No links in emails.

## Server Changes

### Handlers (auth_handler.go)
1. **ForgotPassword** - Modified to:
   - Generate 6-digit code instead of 32-byte token
   - Code expires in 10 minutes (changed from 1 hour)
   - Send code via email (not a link)
   - Response: `{"message": "if account exists, reset code sent"}`

2. **VerifyResetCode** - New endpoint:
   - Validates 6-digit code against email
   - Checks code hasn't expired or been used
   - Returns 200 if valid, 400 if invalid/expired
   - Request: `{email, code}`
   - No token issued at this stage (code just verified)

3. **ResetPassword** - Modified to:
   - Accept `email`, `code`, `password`, `confirm_password` (not token)
   - Validates code again server-side
   - Updates password and revokes refresh tokens
   - Marks code as used

### Email Templates (internal/email/templates/reset_password.html)
- Changed from link format to clean code display
- Shows 6-digit code in large monospace font
- Displays 10-minute expiration
- Includes security note: "Do not share this code"

### Email Sender (internal/email/smtp.go)
- **SendPasswordReset** signature changed: `(toEmail, code string)` instead of `(toEmail, resetURL string)`
- Template data now uses `{code, expires}` instead of `{reset_url, expires}`
- Template validation data updated to match

### API Routes (internal/handlers/app.go)
Added new route:
- `POST /api/v1/auth/verify-reset-code` - Verify the 6-digit code

### Database
- Reuses existing `password_resets` table
- `token_hash` field stores SHA256 hash of 6-digit code
- `expires_at` now 10 minutes (was 1 hour)
- Same cleanup/used tracking as before

## Client Changes

### Flutter Screens

#### ForgotPasswordScreen (modified)
- Input: Email address only
- Action: Calls `POST /auth/forgot-password`
- Navigation: Navigates to ResetCodeScreen with email as parameter
- UI Change: Button text "Send reset code" (was "Send reset link")

#### ResetCodeScreen (new file: reset_code_screen.dart)
- 6 individual digit input boxes
- Auto-focus navigation between fields
- Only allows digits (0-9)
- Field validation (must be 6 digits before submit)
- Calls `POST /auth/verify-reset-code` with email and code
- On success: Navigates to NewPasswordScreen with email and code

#### NewPasswordScreen (new file: new_password_screen.dart)
- New password input field
- Confirm password input field
- Calls `POST /auth/reset-password` with email, code, and passwords
- On success: Redirects to login with success message

### Router Changes (go_router.dart)
- Removed: ResetPasswordScreen import and `/auth/reset` route
- Added:
  - `ResetCodeScreen` import
  - `NewPasswordScreen` import
  - `/auth/reset-code` route (receives email via extra parameter)
  - `/auth/new-password` route (receives email via extra parameter, code via query parameter)

## API Documentation (openapi.yaml)
Updated endpoints:
- `POST /auth/forgot-password` - Now sends code instead of link
- `POST /auth/verify-reset-code` - New endpoint to verify code
- `POST /auth/reset-password` - Now accepts email+code instead of token
- Updated schema for ResetPasswordRequest

## Flow Diagram

```
User: "I forgot my password" 
  ↓
[ForgotPasswordScreen] 
  - Enter email
  - Click "Send reset code"
  ↓
Server: POST /auth/forgot-password
  - Generate 6-digit code
  - Send email with code
  ↓
[ResetCodeScreen]
  - Show 6 digit input boxes
  - User enters code from email
  - Click "Verify code"
  ↓
Server: POST /auth/verify-reset-code
  - Validate code (not expired, not used)
  - Return 200 if valid
  ↓
[NewPasswordScreen]
  - Enter new password
  - Confirm password
  - Click "Reset password"
  ↓
Server: POST /auth/reset-password
  - Validate code again
  - Update user password
  - Mark code as used
  - Revoke refresh tokens
  ↓
[LoginScreen]
  - Show success message
  - User logs in with new password
```

## Testing Results

All endpoints verified and responding:
- ✅ POST /auth/forgot-password: 200 OK
- ✅ POST /auth/verify-reset-code: 400 Bad Request (proper validation)
- ✅ POST /auth/reset-password: 400 Bad Request (proper validation)

Client validation:
- ✅ flutter analyze: No issues found
- ✅ dart format: All files properly formatted
- ✅ flutter pub get: Dependencies resolved

Server validation:
- ✅ go fmt ./...: Code formatted correctly
- ✅ go test ./...: All packages pass
- ✅ Server startup: Migrations run successfully, server listens on :8080

## Security Features

1. **Code Expiration**: 10-minute window matches email verification flow
2. **Code Usage**: Once used to reset password, code cannot be reused
3. **Hash Storage**: Codes stored as SHA256 hashes (never plain text)
4. **Email Validation**: Both code verification and reset require valid email
5. **Token Revocation**: All refresh tokens revoked after password reset
6. **No Links**: Zero risk of reset links being shared or intercepted in URLs
7. **No URL Spoofing**: App controls reset flow entirely (not deep links)

## Configuration

No configuration changes needed. System continues to use:
- DATABASE_URL for migrations and data
- SMTP settings for email delivery
- JWT secrets for token generation
- Encryption key for sensitive data

## Rollback Notes

If needed to revert:
1. Restore original auth_handler.go functions
2. Revert reset_password.html email template
3. Remove ResetCodeScreen and NewPasswordScreen
4. Restore old ResetPasswordScreen
5. Update router imports and routes
6. Update OpenAPI documentation
7. Existing password_resets records continue to work as-is

## Future Enhancements

Potential improvements:
- Rate limiting on forgot-password endpoint (currently uses global rate limit)
- Custom code length configuration
- SMS-based code delivery (alternative to email)
- Code resend functionality
- Analytics on reset success/failure rates
- Adaptive timeout based on security level
