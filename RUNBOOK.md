# BimStreaming Runbook

## Prerequisites
- Flutter SDK installed and on PATH (`flutter --version` works)
- Dart SDK installed (bundled with Flutter)
- Go 1.22+ installed and on PATH (`go version` works)
- Windows PowerShell (for provided scripts)
- Local network access to `http://localhost:8080`

## Project Layout
- `client/`: Flutter desktop client
- `server/`: Go API + websocket server

## Environment Variables

### Client
- `BIM_API_URL` (optional): API base URL override for HTTP calls
- `BIM_SIGNAL_URL` (optional): WebSocket URL override for signaling/events

If not set, client defaults to localhost endpoints.

### Server
- `PORT` (optional): HTTP port (default `8080`)
- `JWT_SECRET` (required in non-dev deployments)
- Any DB/storage credentials required by your server configuration

## Install Dependencies

### Client
```powershell
cd client
flutter pub get
```

### Server
```powershell
cd server
go mod download
```

## Run Locally

### 1) Start server
```powershell
cd server
go run .
```
Server listens on `http://localhost:8080` by default.

### 2) Start Flutter client
In a new terminal:
```powershell
cd client
flutter run -d windows
```

## Validation Commands
Run before merging/releasing.

### Client
```powershell
cd client
flutter pub get
dart format lib
flutter analyze
```

### Server
```powershell
cd server
go fmt ./...
go test ./...
```

## Migrations
Current repository state does not contain an automated migration CLI.

Recommended approach:
- Ensure the target database/schema is available before starting the server.
- Apply schema changes using your team-approved SQL/DDL scripts before deployment.
- Keep migration scripts versioned with release notes.

## Seed Data
Current repository state does not contain a dedicated seed script.

Recommended approach:
- Use test fixtures or API-driven setup in dev environments.
- Seed at minimum:
  - one verified user account
  - one user with 2FA enabled
  - one friend relationship
  - one DM conversation
  - one community with at least one member

  ## Seed test data
  ```powershell
  psql $DATABASE_URL -f server/SEED_DATA.sql
  ```

## End-to-End Smoke Journey
1. Launch server and client.
2. Register a new account.
3. Verify account with email/verification code step.
4. Log in with username/email + password.
5. If prompted, complete 2FA.
6. Confirm landing on home/dashboard.
7. Visit friends, DM, communities, notifications.
8. Send a remote invite and accept/decline from another client.
9. Change theme/avatar in settings/profile.
10. Sign out and confirm remembered-login/restore behavior on relaunch.

## Common Errors and Fixes

### Flutter analyze failures
- Run `dart format lib` and rerun `flutter analyze`.
- Check for duplicate symbol definitions after merges.

### 401 Unauthorized from API
- Access token may be expired.
- Client performs silent refresh automatically when refresh token is valid.
- If refresh fails, sign in again.

### WebSocket disconnected
- Ensure server is running and websocket endpoint is reachable.
- Verify token is present and valid.
- Client retries reconnect with backoff automatically.

### Signaling/remote session invitation not delivered
- Check both users are authenticated.
- Ensure both clients are connected to websocket endpoint.
- Verify recipient ID is correct.

## WebSocket Event Reference

| Event | Direction | Purpose | Expected Client Action |
|---|---|---|---|
| `connection_request` | server -> client | Incoming remote support request | Show invite modal with timeout |
| `connection_accept` | peer -> peer | Invite accepted | Start session handshake |
| `connection_reject` | peer -> peer | Invite declined | Show decline feedback and clear pending state |
| `session_message` | peer <-> peer | Session control/data envelope | Route by `messageType` to session handlers |
| `dm:new` | server -> client | New direct message | Append message in conversation and unread counts |
| `dm:typing` | server -> client | Typing started | Show typing indicator |
| `dm:typing_stop` | server -> client | Typing stopped | Clear typing indicator |
| `notification:new` | server -> client | New app notification | Add to notifications list and unread badge |

## Operational Notes
- Log out path sends refresh token revocation then clears local tokens.
- Session restore runs at app bootstrap from secure storage.
- Keep server and client clocks reasonably synchronized for token expiry behavior.
