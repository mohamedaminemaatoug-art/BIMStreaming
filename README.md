# BimStreaming

**Version 1.2.0** — Windows Desktop Remote Support & Community Collaboration Platform

BimStreaming is a full-stack desktop application that combines real-time remote control, community collaboration, direct messaging, and social features into a single Windows application.

---

## Architecture Overview

```
BimStreaming/
├── client/      # Flutter Windows desktop application (UI, screen capture, input injection)
└── server/      # Go REST API + WebSocket relay server (transport, auth, persistence)
```

### Component Responsibilities

| Layer | Technology | Role |
|-------|-----------|------|
| **Client** | Flutter 3.11+ / Dart | UI rendering, screen capture (DXGI/VP9), keyboard & mouse injection, state management |
| **Server** | Go 1.21+ / chi router | REST API, JWT authentication, WebSocket relay, PostgreSQL persistence |
| **Database** | PostgreSQL 16+ | All persistent data (users, sessions, communities, messages) |
| **Real-time** | WebSocket (gorilla/websocket) | Presence broadcasting, session signaling, remote stream relay |

> The server is a **transparent relay** — it routes binary VP9 video frames and JSON session messages between clients without parsing payloads. All capture and injection logic lives exclusively in the Flutter client.

---

## Architecture Diagram

```
┌──────────────────────────────────────────────────────────┐
│                  Flutter Client (Windows)                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │
│  │  Riverpod │  │ GoRouter │  │  DXGI    │  │  Win32  │ │
│  │  State   │  │  Routing │  │ Capturer │  │  Input  │ │
│  └────┬─────┘  └──────────┘  └────┬─────┘  └────┬────┘ │
│       │                            │              │       │
│  ┌────▼───────────────────────────▼──────────────▼────┐  │
│  │           API Client + WS Client + Signaling        │  │
│  └──────────────────────┬──────────────────────────────┘  │
└─────────────────────────│──────────────────────────────────┘
                           │ HTTP REST + WebSocket
┌──────────────────────────▼──────────────────────────────────┐
│                    Go Server (:8080)                          │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │  chi Router  │  │  WS Router   │  │   WS Hub           │  │
│  │  REST API    │  │  (relay)     │  │  (presence/events) │  │
│  └──────┬──────┘  └──────┬───────┘  └────────────────────┘  │
│         │                │                                    │
│  ┌──────▼──────────────────────────────────────────────────┐  │
│  │          Handlers → Repository → PostgreSQL              │  │
│  └──────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
                           │
              ┌────────────▼────────────┐
              │  PostgreSQL (port 5432)  │
              │  25+ tables, migrations  │
              └─────────────────────────┘
```

---

## Quick Start

### Prerequisites

- Go 1.21+
- Flutter 3.11+ (Windows target)
- PostgreSQL 16+
- `golang-migrate` CLI

### Start everything (recommended)

```powershell
.\start-dev.ps1 -SignalUrl ws://192.168.1.207:8080/api/v1/ws
```

**Options:**

| Flag | Description |
|------|-------------|
| `-SkipBackend` | Start client only |
| `-LowMemory` | Reduce Flutter memory footprint |
| `-Mode debug\|profile\|release` | Flutter build mode (default: `debug`) |

### Server only

```powershell
cd server
go run .
```

### Client only

```powershell
cd client
flutter run -d windows --dart-define=BIM_SIGNAL_URL=ws://192.168.1.207:8080/api/v1/ws
```

---

## Server Configuration

Create `server/.env`:

```env
DATABASE_URL=postgres://user:pass@host:5432/bimstreaming?sslmode=require
SERVER_ADDR=0.0.0.0:8080
JWT_SECRET=<32-byte hex>
JWT_REFRESH_SECRET=<32-byte hex>
ENCRYPTION_KEY=<32-char string>
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=noreply@example.com
SMTP_PASS=<password>
SMTP_FROM=BimStreaming <noreply@example.com>
APP_BASE_URL=http://192.168.1.207:8080
AVATAR_STORAGE_PATH=./storage/avatars
MAX_UPLOAD_SIZE_MB=5
RATE_LIMIT_ENABLED=false
```

### Run database migrations

```powershell
# Apply all migrations
migrate -path .\server\migrations -database "$env:DATABASE_URL" up

# Rollback one migration
migrate -path .\server\migrations -database "$env:DATABASE_URL" down 1
```

---

## API Reference

Base path: `/api/v1` | Full spec: [`server/openapi.yaml`](server/openapi.yaml)

### Authentication

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/auth/register` | Register with email + password |
| POST | `/auth/verify-email` | Confirm email address |
| POST | `/auth/login` | Login (returns JWT pair) |
| POST | `/auth/2fa/challenge` | Submit TOTP code |
| POST | `/auth/2fa/setup` | Enable 2FA |
| POST | `/auth/refresh` | Refresh access token |
| POST | `/auth/logout` | Revoke refresh token |
| POST | `/auth/forgot-password` | Request password reset code |
| POST | `/auth/reset-password` | Apply new password |

### Users & Profiles

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/users/me` | Get own profile |
| PATCH | `/users/me` | Update profile |
| POST | `/users/me/avatar` | Upload avatar (≤5 MB) |
| GET | `/users/search` | Search users |
| GET | `/users/{id}` | Get public profile |
| GET/PATCH | `/users/me/status` | Get or update custom status |
| GET | `/users/me/export` | GDPR data export |
| POST | `/users/me/delete` | Request account deletion |

### Friends

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/friends` | List accepted friends |
| GET | `/friends/requests` | Pending requests |
| POST | `/friends/request/{user_id}` | Send friend request |
| PATCH | `/friends/request/{id}` | Accept or reject |
| DELETE | `/friends/{user_id}` | Remove friend |
| POST/DELETE | `/friends/block/{user_id}` | Block / unblock |

### Communities

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/communities` | List joined communities |
| POST | `/communities` | Create community |
| GET | `/communities/discover` | Browse public communities |
| POST | `/communities/join` | Join by invite code |
| GET/PATCH/DELETE | `/communities/{id}` | Read, update, delete |
| GET/POST | `/communities/{id}/messages` | Channel messages |
| GET/POST | `/communities/{id}/announcements` | Announcements |
| GET/POST | `/communities/{id}/members` | Member management |
| POST | `/communities/{id}/members/{user_id}/ban` | Ban member |
| POST/PATCH | `/communities/{id}/departments` | Department management |

### Direct Messages

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/dm` | List conversations |
| GET | `/dm/{user_id}` | Message history |
| POST | `/dm/{user_id}` | Send message |
| PATCH | `/dm/{user_id}/read` | Mark as read |

### Remote Sessions

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/remote/invite/{user_id}` | Send remote access invitation |
| PATCH | `/remote/invite/{id}` | Accept or reject invitation |
| POST | `/remote/sessions` | Create session |
| GET | `/remote/sessions/{id}` | Session details |
| PATCH | `/remote/sessions/{id}/permissions` | Update permissions |
| PATCH | `/remote/sessions/{id}/quality` | Set stream quality |
| POST | `/remote/sessions/{id}/end` | End session |
| POST/GET/DELETE | `/remote/unattended-access` | Unattended access tokens |
| GET | `/remote/history` | Session history |

### Notifications

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/notifications` | List notifications |
| PATCH | `/notifications/read` | Mark all as read |
| PATCH | `/notifications/{id}/read` | Mark one as read |

### Admin

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/admin/users` | List all users |
| POST | `/admin/users/{id}/ban` | Ban user |
| GET | `/admin/communities` | List communities |
| GET | `/admin/sessions/active` | Live sessions |
| GET | `/admin/stats` | Platform statistics |
| GET | `/admin/audit` | Audit log |

### WebSocket

```
GET /api/v1/ws?token=<access_token>
```

**Message envelope (JSON):**

```json
{
  "type": "connection_request | connection_accept | connection_reject | session_message | register",
  "session_id": "<uuid>",
  "from": "<user_id>",
  "to": "<user_id>",
  "payload": {}
}
```

**Binary VP9 frame envelope:**

```
[0]    0xB1  — magic byte 0
[1]    0x4D  — magic byte 1
[2-3]  version (ignored)
[4-7]  uint32LE: length of target client ID (N)
[8..8+N-1]  target client ID (UTF-8)
[rest]  session ID + flags + width + height + VP9 bitstream
```

---

## Database Migrations

| Migration | Tables Created |
|-----------|---------------|
| `001_init` | `pgcrypto` extension, `set_updated_at()` trigger function |
| `002_auth_core` | `users`, `email_verifications`, `password_resets`, `refresh_tokens`, `device_sessions` |
| `003_communities` | `communities`, `departments`, `community_members`, `join_requests` |
| `004_social_messages` | `friendships`, `direct_messages`, `community_messages`, `notifications` |
| `005_remote_activity` | `remote_session_invites`, `activity_log` |
| `006_production_additions` | `totp_backup_codes`, `audit_logs`, `login_history`, `trusted_devices`, `user_status`, `remote_sessions`, `session_permissions`, `unattended_access`, `plans`, `user_subscriptions`, `push_tokens`, `community_announcements`, `community_invites`, `community_bans`, `message_reactions`, `message_attachments` |
| `007_security_additions` | User lockout fields (`locked_until`, `failed_login_count`, `is_banned`) |
| `008_push_admin_gdpr` | `data_export_requests`, `account_deletion_requests` |

---

## Project Structure

```
BimStreaming/
├── client/
│   ├── lib/
│   │   ├── main.dart                    # Entry point (ProviderScope)
│   │   ├── app/
│   │   │   ├── router.dart              # GoRouter route definitions
│   │   │   ├── pages/auth/              # 7 authentication screens
│   │   │   ├── pages/profile_screen.dart
│   │   │   ├── state/
│   │   │   │   ├── auth_controller.dart # Login/register/2FA flow
│   │   │   │   ├── data_providers.dart  # Riverpod providers
│   │   │   │   └── realtime_controller.dart  # WebSocket lifecycle
│   │   │   └── widgets/app_shell.dart   # Navigation shell
│   │   ├── screens/                     # Feature screens
│   │   │   ├── friends_screen.dart
│   │   │   ├── communities_screen.dart
│   │   │   ├── notifications_screen.dart
│   │   │   └── remote_support_page.dart
│   │   ├── services/
│   │   │   ├── api_client.dart          # HTTP REST client
│   │   │   ├── ws_client.dart           # WebSocket client
│   │   │   ├── signaling_client_service.dart  # Remote session signaling
│   │   │   ├── file_transfer_service.dart
│   │   │   ├── remote_audio_service.dart
│   │   │   └── app_config.dart
│   │   ├── native/
│   │   │   ├── dxgi_capturer.dart       # DXGI screen capture (Win32 FFI)
│   │   │   └── vp9_codec.dart           # VP9 encode/decode
│   │   └── services/keyboard/
│   │       ├── keyboard_host_injection_engine.dart
│   │       ├── keyboard_input_abstraction.dart
│   │       └── keyboard_protocol.dart
│   ├── windows/
│   │   ├── CMakeLists.txt
│   │   └── runner/bimstreaming_codec.dll  # Native VP9 codec
│   └── pubspec.yaml
│
└── server/
    ├── main.go                          # Bootstrap: migrations + HTTP server
    ├── router.go                        # WebSocket upgrade + relay logic
    ├── clients.go                       # In-memory client registry
    ├── sessions.go                      # In-memory session registry
    ├── internal/
    │   ├── handlers/
    │   │   ├── app.go                   # Route mounting
    │   │   ├── auth_handler.go
    │   │   ├── communities_handler.go
    │   │   ├── friends_handler.go
    │   │   ├── dm_handler.go
    │   │   ├── remote_handler.go
    │   │   ├── remote_sessions_handler.go
    │   │   └── notifications_handler.go
    │   ├── repository/                  # Data access layer (one file per domain)
    │   ├── models/models.go             # All data structs
    │   ├── auth/                        # JWT, bcrypt, TOTP, AES-256
    │   ├── middleware/                  # Logging, auth, plan enforcement, audit
    │   ├── ws/                          # WebSocket hub (presence & events)
    │   ├── email/                       # SMTP sender
    │   ├── geoip/                       # IP geolocation
    │   ├── push/                        # Push notification dispatcher
    │   └── storage/                     # Avatar & attachment file service
    ├── migrations/                      # SQL migration files (001–008)
    ├── openapi.yaml                     # Full OpenAPI 3.0 specification
    └── build/bimstreaming-server.exe    # Compiled server binary
```

---

## Features

| Category | Features |
|----------|---------|
| **Authentication** | Email/password, email verification, TOTP 2FA + backup codes, password reset, JWT access + refresh tokens, device fingerprinting, account lockout |
| **Security** | Login history with GeoIP, trusted device management, AES-256 payload encryption, audit logging, GDPR data export & account deletion |
| **User Profiles** | Avatar upload, display name, bio, custom status (emoji + availability), language, timezone, theme (dark/light/system) |
| **Social** | Friend requests, blocking, real-time presence broadcast, direct messaging (1:1), message reactions, file attachments |
| **Communities** | Create/join by code, hierarchical (Community → Department), roles (owner/admin/admin_sec/tech/user/viewer), announcements, threaded messages, reactions, invites, join request approval, member bans, audit log |
| **Remote Control** | Session invitation flow, Controller ↔ Agent relay, VP9 screen streaming at 30–60 fps (DXGI capture), keyboard injection, mouse injection, audio streaming, file transfer, unattended access tokens, granular permissions, session quality control |
| **Subscriptions** | Free / Pro / Team / Enterprise plans, plan enforcement middleware (concurrent sessions, community limits, feature gating) |
| **Admin** | User list/ban/unban, community management, active session monitoring, platform statistics, audit log |

---

## Build

### Server binary

```powershell
cd server
go build -o build/bimstreaming-server.exe .
```

### Client release

```powershell
cd client
flutter build windows --release --dart-define=BIM_SIGNAL_URL=ws://YOUR_IP:8080/api/v1/ws
```

---

## Conventions

- **Server**: Repository pattern — handlers call repository methods only, never raw SQL in handlers
- **Server**: All HTTP responses are JSON; errors use `{"error": "message"}`
- **Client**: UI never calls the API directly — all calls go through Riverpod providers
- **Client**: Credentials stored in `flutter_secure_storage`
- **WebSocket auth**: JWT passed as `?token=<access_token>` query parameter
- **OpenAPI spec** (`server/openapi.yaml`) is authoritative for all endpoint contracts
