# Architecture du Système BimStreaming

## Table des Matières

1. [Vue d'ensemble du système](#1-vue-densemble-du-système)
2. [Stack Technologique](#2-stack-technologique)
3. [Architecture Générale](#3-architecture-générale)
4. [Architecture Backend (Go)](#4-architecture-backend-go)
   - [Structure du serveur](#41-structure-du-serveur)
   - [API REST — Tous les endpoints](#42-api-rest--tous-les-endpoints)
   - [Protocole WebSocket](#43-protocole-websocket)
   - [Middlewares](#44-middlewares)
5. [Architecture Base de Données (PostgreSQL)](#5-architecture-base-de-données-postgresql)
   - [Schéma complet](#51-schéma-complet)
   - [Diagramme entité-relation](#52-diagramme-entité-relation)
6. [Architecture Client (Flutter)](#6-architecture-client-flutter)
   - [Structure du projet](#61-structure-du-projet)
   - [Gestion d'état (Riverpod)](#62-gestion-détat-riverpod)
   - [Navigation (GoRouter)](#63-navigation-gorouter)
7. [Flux d'Authentification et Sécurité](#7-flux-dauthentification-et-sécurité)
8. [Pipeline de Contrôle à Distance](#8-pipeline-de-contrôle-à-distance)
   - [Flux d'invitation](#81-flux-dinvitation)
   - [Pipeline vidéo VP9](#82-pipeline-vidéo-vp9)
   - [Couche native (Rust FFI)](#83-couche-native-rust-ffi)
9. [Architecture de Messagerie en Temps Réel](#9-architecture-de-messagerie-en-temps-réel)
10. [Architecture de Sécurité](#10-architecture-de-sécurité)
11. [Performances et Optimisations](#11-performances-et-optimisations)

---

## 1. Vue d'ensemble du système

**BimStreaming** est une plateforme de contrôle à distance et de collaboration en temps réel pour desktop Windows. Elle permet à des utilisateurs de prendre le contrôle d'un écran distant, de communiquer via messagerie instantanée, et de s'organiser en communautés.

### Fonctionnalités principales

| Fonctionnalité | Description |
|---|---|
| Contrôle à distance | Capture d'écran DXGI, codec VP9, injection clavier/souris |
| Messagerie | DM 1:1 et chat de communauté en temps réel |
| Système social | Amis, blocages, présence en ligne |
| Communautés | Groupes avec rôles (owner/admin/user/viewer) |
| Authentification | JWT + 2FA TOTP + appareils de confiance |
| Accès non supervisé | Connexion pré-autorisée sans validation |

---

## 2. Stack Technologique

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         BIMSTREAMING SYSTEM                             │
├────────────────────┬────────────────────┬───────────────────────────────┤
│   CLIENT           │   TRANSPORT        │   SERVEUR                     │
│   Flutter / Dart   │                    │   Go + Chi                    │
│   Windows Desktop  │   REST (HTTP)      │   REST API                    │
│                    │   WebSocket        │   WebSocket Hub               │
│   Riverpod         │   Binary Frames    │   PostgreSQL                  │
│   GoRouter         │   JWT Bearer       │   JWT / TOTP                  │
│   VP9 Decoder      │                    │   SMTP / FCM                  │
│   DXGI Capturer    │                    │   VP9 Encoder (Rust FFI)      │
│   Rust FFI         │                    │                               │
└────────────────────┴────────────────────┴───────────────────────────────┘
```

| Couche | Technologie | Version |
|---|---|---|
| Backend | Go | 1.25+ |
| Router HTTP | Chi | v5.2.5 |
| Base de données | PostgreSQL | 13+ |
| Driver DB | pgx + sqlx | v5.9.1 / v1.4.0 |
| Authentification | golang-jwt | v5.3.1 |
| WebSocket (serveur) | Gorilla WebSocket | v1.5.3 |
| Frontend | Flutter + Dart | 3.11+ |
| Gestion d'état | Flutter Riverpod | 2.6.1 |
| Navigation | GoRouter | 16.1.0 |
| Client HTTP | http (Dart) | 1.2.2 |
| WebSocket (client) | web_socket_channel | 3.0.1 |
| Stockage sécurisé | flutter_secure_storage | 9.0.0 |
| Codec vidéo | VP9 (Rust FFI) | custom |
| Capture écran | DXGI (DirectX 11) | Windows |
| Notifications push | Firebase FCM | — |
| Email | SMTP | — |
| Crypto | bcrypt + AES-256 | Go std |

---

## 3. Architecture Générale

```
┌──────────────────────────────────────────────────────────────────────┐
│                        ARCHITECTURE GLOBALE                          │
└──────────────────────────────────────────────────────────────────────┘

  ┌────────────────────────────────┐
  │   CLIENT FLUTTER (Windows)     │
  │                                │
  │  ┌──────────────────────────┐  │         HTTPS / WSS
  │  │       UI (Screens)       │  │  ◄────────────────────────►
  │  │  Home / Auth / Social    │  │
  │  └──────────┬───────────────┘  │
  │             │ Riverpod         │
  │  ┌──────────▼───────────────┐  │
  │  │     State Controllers    │  │         ┌─────────────────────────┐
  │  │  Auth / Friends /        │  │         │       GO SERVER         │
  │  │  Realtime / Remote       │  │         │                         │
  │  └──────────┬───────────────┘  │         │  ┌───────────────────┐  │
  │             │                  │  REST   │  │   Chi Router      │  │
  │  ┌──────────▼───────────────┐  │ ──────► │  │  /api/v1/...     │  │
  │  │      Services            │  │         │  └────────┬──────────┘  │
  │  │  ApiClient               │  │         │           │             │
  │  │  WsClient                │  │  WS     │  ┌────────▼──────────┐  │
  │  │  SignalingService        │  │ ──────► │  │  WebSocket Hub    │  │
  │  └──────────┬───────────────┘  │         │  │  + Router         │  │
  │             │                  │         │  └────────┬──────────┘  │
  │  ┌──────────▼───────────────┐  │         │           │             │
  │  │   Native Layer (FFI)     │  │         │  ┌────────▼──────────┐  │
  │  │  Vp9Codec (Rust)         │  │ Binary  │  │   Handlers        │  │
  │  │  DxgiCapturer (DXGI)     │  │ ──────► │  │  Auth/Friends/    │  │
  │  │  KeyboardEngine (Win32)  │  │         │  │  Remote/          │  │
  │  └──────────────────────────┘  │         │  │  Communities      │  │
  └────────────────────────────────┘         │  └────────┬──────────┘  │
                                              │           │             │
                                              │  ┌────────▼──────────┐  │
                                              │  │   Repository      │  │
                                              │  │   (Data Access)   │  │
                                              │  └────────┬──────────┘  │
                                              │           │             │
                                              └───────────┼─────────────┘
                                                          │
                                              ┌───────────▼─────────────┐
                                              │    PostgreSQL Database   │
                                              │  users, sessions,        │
                                              │  friends, communities,   │
                                              │  messages, remote_...    │
                                              └─────────────────────────┘
```

---

## 4. Architecture Backend (Go)

### 4.1 Structure du serveur

```
server/
├── main.go                         ← Point d'entrée
├── router.go                       ← WebSocket Hub + routage frames
├── internal/
│   ├── handlers/
│   │   ├── app.go                  ← AppHandler (regroupement dépendances)
│   │   ├── auth_handler.go         ← Auth endpoints
│   │   ├── users_handler.go        ← Profil utilisateur
│   │   ├── friends_handler.go      ← Amis & blocages
│   │   ├── dm_handler.go           ← Messages directs
│   │   ├── remote_handler.go       ← Invitations de session
│   │   ├── remote_sessions_handler.go ← Sessions actives
│   │   ├── communities_handler.go  ← Communautés
│   │   ├── notifications_handler.go
│   │   ├── admin_handler.go
│   │   └── security_handler.go
│   ├── repository/
│   │   ├── users.go                ← CRUD utilisateurs
│   │   ├── auth.go                 ← Tokens, devices
│   │   ├── friends.go              ← Amitiés
│   │   ├── messages.go             ← DM
│   │   ├── communities.go          ← Communautés
│   │   ├── remote.go               ← Sessions distantes
│   │   └── notifications.go
│   ├── middleware/
│   │   ├── logging.go              ← Request logger
│   │   ├── auth.go                 ← JWT validation (RequireAuth)
│   │   ├── rate_limiter.go         ← Rate limiting par IP
│   │   ├── audit.go                ← Audit log des actions
│   │   └── plan_enforcer.go        ← Feature flags par plan
│   └── storage/
│       ├── avatars.go              ← Upload/resize avatar
│       └── attachments.go          ← Fichiers joints
└── .env                            ← Config (DATABASE_URL, JWT_SECRET, ...)
```

#### Initialisation (`main.go`)

```
main.go
 │
 ├── Chargement .env
 │    DATABASE_URL, JWT_SECRET, ENCRYPTION_KEY,
 │    SMTP_HOST/USER/PASS, FCM_KEY, GEO_API_KEY
 │
 ├── Connexion PostgreSQL (pool: 25 conn, 5 min timeout)
 │
 ├── Instanciation composants:
 │    ├── TokenManager        (JWT HS256)
 │    ├── Repository          (accès DB)
 │    ├── Hub                 (présence + broadcasting WS)
 │    ├── EmailSender         (SMTP)
 │    ├── GeoIPClient
 │    ├── AvatarStorage
 │    ├── AttachmentStorage
 │    └── FCMDispatcher       (Firebase push)
 │
 └── Démarrage Chi router sur :8080
```

### 4.2 API REST — Tous les endpoints

> Préfixe commun : `/api/v1`

#### Authentification

| Méthode | Route | Description |
|---|---|---|
| POST | `/auth/register` | Inscription (username, email, password) |
| POST | `/auth/verify-email` | Vérification email (OTP) |
| POST | `/auth/resend-verification` | Renvoyer le code de vérification |
| POST | `/auth/login` | Connexion → access_token + refresh_token |
| POST | `/auth/2fa/setup` | Activer 2FA (génère secret TOTP) |
| POST | `/auth/2fa/challenge` | Valider code TOTP (avec temp_token) |
| POST | `/auth/2fa/verify` | Vérifier code TOTP (authentifié) |
| POST | `/auth/2fa/disable` | Désactiver 2FA |
| POST | `/auth/2fa/backup` | Générer codes de secours |
| POST | `/auth/refresh` | Renouveler access_token via refresh_token |
| POST | `/auth/logout` | Déconnexion (révoque refresh_token) |
| POST | `/auth/forgot-password` | Demande de réinitialisation (email) |
| POST | `/auth/verify-reset-code` | Vérifier OTP de réinitialisation |
| POST | `/auth/reset-password` | Nouveau mot de passe |
| POST | `/auth/change-password` | Changer mot de passe (authentifié) |

#### Utilisateurs

| Méthode | Route | Description |
|---|---|---|
| GET | `/users/me` | Profil de l'utilisateur courant |
| PATCH | `/users/me` | Modifier profil (nom, avatar, thème, langue) |
| PATCH | `/users/me/notifications` | Préférences de notification |
| POST | `/users/me/avatar` | Uploader avatar |
| GET | `/users/me/status` | Lire statut (emoji, disponibilité) |
| PATCH | `/users/me/status` | Mettre à jour statut |
| GET | `/users/me/export` | Exporter ses données |
| POST | `/users/me/delete` | Supprimer compte |
| GET | `/users/{id}` | Profil public d'un utilisateur |
| GET | `/users/{id}/status` | Statut d'un utilisateur |
| GET | `/users/search` | Rechercher des utilisateurs |

#### Amis

| Méthode | Route | Description |
|---|---|---|
| GET | `/friends` | Lister amis acceptés |
| GET | `/friends/requests` | Demandes en attente (envoyées et reçues) |
| GET | `/friends/blocked` | Utilisateurs bloqués |
| POST | `/friends/request/{user_id}` | Envoyer demande d'amitié |
| PATCH | `/friends/request/{id}` | Accepter / Refuser une demande |
| DELETE | `/friends/{user_id}` | Supprimer un ami |
| POST | `/friends/block/{user_id}` | Bloquer un utilisateur |
| DELETE | `/friends/block/{user_id}` | Débloquer un utilisateur |

#### Messages Directs

| Méthode | Route | Description |
|---|---|---|
| GET | `/dm` | Lister conversations (paginé) |
| GET | `/dm/{user_id}` | Historique avec un utilisateur |
| POST | `/dm/{user_id}` | Envoyer un message |
| PATCH | `/dm/{user_id}/read` | Marquer comme lu |

#### Sessions Distantes

| Méthode | Route | Description |
|---|---|---|
| POST | `/remote/invite/{user_id}` | Créer une invitation de session |
| PATCH | `/remote/invite/{id}` | Accepter / Refuser une invitation |
| POST | `/remote/sessions` | Créer session active |
| GET | `/remote/sessions/{id}` | Détails d'une session |
| PATCH | `/remote/sessions/{id}` | Modifier session |
| PATCH | `/remote/sessions/{id}/permissions` | Modifier permissions |
| PATCH | `/remote/sessions/{id}/quality` | Modifier qualité vidéo |
| GET | `/remote/history` | Historique des sessions |
| POST | `/remote/unattended-access` | Configurer accès non supervisé |
| GET | `/remote/unattended-access` | Lister accès non supervisés |

#### Communautés

| Méthode | Route | Description |
|---|---|---|
| POST | `/communities` | Créer une communauté |
| GET | `/communities` | Mes communautés |
| GET | `/communities/discover` | Découvrir communautés publiques |
| POST | `/communities/join` | Rejoindre via code |
| GET | `/communities/{id}` | Détails d'une communauté |
| PATCH | `/communities/{id}` | Modifier communauté |
| DELETE | `/communities/{id}` | Supprimer communauté |
| GET | `/communities/{id}/members` | Lister membres |
| POST | `/communities/{id}/members` | Ajouter membre |
| PATCH | `/communities/{id}/members/{user_id}` | Modifier rôle |
| DELETE | `/communities/{id}/members/{user_id}` | Exclure membre |
| POST | `/communities/{id}/members/{user_id}/ban` | Bannir membre |
| DELETE | `/communities/{id}/members/{user_id}/ban` | Lever bannissement |
| POST | `/communities/{id}/request-join` | Demande d'adhésion |
| GET | `/communities/{id}/join-requests` | Demandes d'adhésion |
| PATCH | `/communities/{id}/join-requests/{req_id}` | Approuver/Rejeter demande |
| POST | `/communities/{id}/invite` | Inviter un utilisateur |
| GET | `/communities/{id}/invite-codes` | Codes d'invitation |
| GET | `/communities/{id}/announcements` | Annonces |
| POST | `/communities/{id}/announcements` | Créer annonce |
| PATCH | `/communities/{id}/announcements/{id}` | Modifier annonce |
| DELETE | `/communities/{id}/announcements/{id}` | Supprimer annonce |
| GET | `/communities/{id}/messages` | Messages du groupe |
| POST | `/communities/{id}/messages` | Envoyer message |
| PATCH | `/communities/{id}/messages/{id}` | Modifier message |
| DELETE | `/communities/{id}/messages/{id}` | Supprimer message |
| GET/POST/DELETE | `/communities/{id}/messages/{id}/reactions` | Réactions |
| GET/POST | `/communities/{id}/messages/{id}/attachments` | Pièces jointes |
| POST | `/communities/{id}/departments` | Créer département |
| PATCH | `/communities/{id}/departments/{id}` | Modifier département |
| DELETE | `/communities/{id}/departments/{id}` | Supprimer département |
| GET | `/communities/{id}/audit` | Journal d'audit |

#### Administration

| Méthode | Route | Description |
|---|---|---|
| GET | `/admin/audit` | Journal d'audit global |
| GET | `/admin/users` | Lister tous les utilisateurs |
| GET | `/admin/users/{id}` | Détails d'un utilisateur |
| POST | `/admin/users/{id}/ban` | Bannir un utilisateur |
| POST | `/admin/users/{id}/unban` | Lever bannissement |
| POST | `/admin/users/{id}/verify` | Forcer vérification |
| GET | `/admin/communities` | Toutes les communautés |
| GET | `/admin/sessions` | Toutes les sessions |
| GET | `/admin/sessions/active` | Sessions actives |
| GET | `/admin/stats` | Statistiques système |

#### Sécurité et Notifications

| Méthode | Route | Description |
|---|---|---|
| GET | `/security/login-history` | Historique des connexions |
| GET | `/security/trusted-devices` | Appareils de confiance |
| DELETE | `/security/trusted-devices/{id}` | Révoquer un appareil |
| POST | `/security/revoke-all-sessions` | Révoquer toutes les sessions |
| POST | `/push/register` | Enregistrer token FCM |
| DELETE | `/push/unregister` | Désinscrire token FCM |
| GET | `/subscriptions/me` | Plan d'abonnement |
| GET | `/ws` | **WebSocket upgrade** |

### 4.3 Protocole WebSocket

```
┌─────────────────────────────────────────────────────────────────┐
│  Connexion WebSocket                                            │
│  GET /api/v1/ws?token=<JWT>&user_id=<ID>&client_id=<ID>        │
└─────────────────────────────────────────────────────────────────┘

MESSAGES TEXTE (JSON) — Signalisation
──────────────────────────────────────
Envelope:
{
  "type":       "register | connection_request | session_message | ...",
  "session_id": "uuid",
  "from":       "user_id",
  "to":         "user_id",
  "data":       { ... },
  "payload":    { ... }
}

Types d'événements:
  register              ← Client s'enregistre (role: host | viewer)
  connection_request    ← Initier connexion vers un peer
  connection_accept     ← Peer accepte
  connection_reject     ← Peer refuse
  session_message       ← Relay de données au sein d'une session

Événements serveur → client:
  user:online           ← Un ami vient de se connecter
  user:offline          ← Un ami s'est déconnecté
  remote:invite         ← Nouvelle invitation de session distante
  remote:invite_rejected ← Invitation refusée
  remote:session_started ← Session créée, les deux peers peuvent se connecter
  remote:session_ended  ← Session terminée
  friend:request        ← Demande d'amitié reçue
  friend:accepted       ← Demande d'amitié acceptée

MESSAGES BINAIRES — Frames VP9
──────────────────────────────
Format d'enveloppe:
  [0]     = 0xB1          (magic byte 0)
  [1]     = 0x4D          (magic byte 1)
  [2-3]   = version       (2 octets little-endian, non utilisé)
  [4-7]   = toIDLen       (uint32 LE: longueur de l'ID destinataire)
  [8..N]  = toClientID    (UTF-8 string, N = toIDLen octets)
  [N..]   = VP9 payload   (données vidéo encodées)

Routage:
  handleBinaryVideoFrame(msg)
    ├─ Extraire toClientID depuis l'enveloppe
    ├─ Chercher connexion dans clientRegistry
    └─ Forwarder le message binaire (non-blocking, drop si queue pleine)
```

### 4.4 Middlewares

```
Requête entrante
      │
      ▼
┌─────────────────────┐
│  RequestLogger      │  Log: méthode, URL, IP, durée, status
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  RateLimiter        │  200 req/min global (IP); 10 req/min auth
│                     │  → 429 Too Many Requests si dépassé
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  RequireAuth        │  Valide JWT Bearer token
│                     │  Extrait: userID, deviceID, role → context
│                     │  → 401 si absent/expiré/invalide
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  PlanEnforcer       │  Feature gates selon le plan d'abonnement
│                     │  (max sessions, max communautés, etc.)
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  AuditLog           │  Enregistre actions sensibles en base
│  (select endpoints) │  (ban, kick, delete, etc.)
└─────────┬───────────┘
          │
          ▼
       Handler
```

---

## 5. Architecture Base de Données (PostgreSQL)

### 5.1 Schéma complet

#### Gestion des utilisateurs et authentification

```sql
-- Compte utilisateur
users (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username                TEXT UNIQUE NOT NULL,
  email                   TEXT UNIQUE NOT NULL,
  phone                   TEXT UNIQUE,
  password_hash           TEXT NOT NULL,
  device_id               TEXT UNIQUE,              -- SHA256(email + uuid)
  avatar_url              TEXT,
  display_name            TEXT,
  bio                     TEXT,
  language                TEXT DEFAULT 'en',
  timezone                TEXT DEFAULT 'UTC',
  theme                   TEXT DEFAULT 'dark',       -- dark|light|system
  notification_preferences JSONB,
  two_factor_enabled      BOOLEAN DEFAULT false,
  two_factor_secret       TEXT,                      -- secret TOTP (chiffré)
  is_verified             BOOLEAN DEFAULT false,
  is_online               BOOLEAN DEFAULT false,
  is_banned               BOOLEAN DEFAULT false,
  ban_reason              TEXT,
  is_superadmin           BOOLEAN DEFAULT false,
  failed_login_count      INT DEFAULT 0,
  locked_until            TIMESTAMPTZ,               -- protection brute force
  last_seen_at            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
)

-- Session d'appareil (lie un user à son device_id)
device_sessions (
  id               UUID PRIMARY KEY,
  user_id          UUID REFERENCES users(id),
  device_id        TEXT,
  session_password TEXT,                             -- code 6 chiffres pour invitations
  label            TEXT,                             -- nom de l'appareil
  is_active        BOOLEAN DEFAULT true,
  last_active_at   TIMESTAMPTZ,
  UNIQUE (user_id, device_id)
)

-- Tokens de rafraîchissement JWT
refresh_tokens (
  id                 UUID PRIMARY KEY,
  user_id            UUID REFERENCES users(id),
  token_hash         TEXT NOT NULL,
  device_fingerprint TEXT,
  expires_at         TIMESTAMPTZ NOT NULL,
  revoked_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  updated_at         TIMESTAMPTZ DEFAULT NOW()
)

-- Codes de récupération 2FA
totp_backup_codes (
  id        UUID PRIMARY KEY,
  user_id   UUID REFERENCES users(id),
  code_hash TEXT NOT NULL,
  used_at   TIMESTAMPTZ
)

-- Statut de disponibilité
user_status (
  user_id      UUID PRIMARY KEY REFERENCES users(id),
  status       TEXT,                                 -- available|busy|away|do_not_disturb
  custom_emoji TEXT,
  custom_text  TEXT,
  updated_at   TIMESTAMPTZ DEFAULT NOW()
)
```

#### Social et Messagerie

```sql
-- Relations d'amitié
friendships (
  id           UUID PRIMARY KEY,
  requester_id UUID REFERENCES users(id),
  addressee_id UUID REFERENCES users(id),
  status       TEXT NOT NULL,                        -- pending|accepted|blocked
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT unique_friendship CHECK (requester_id < addressee_id),
  UNIQUE (requester_id, addressee_id)
)

-- Messages directs 1:1
direct_messages (
  id           UUID PRIMARY KEY,
  sender_id    UUID REFERENCES users(id),
  recipient_id UUID REFERENCES users(id),
  reply_to_id  UUID REFERENCES direct_messages(id),
  content      TEXT NOT NULL,
  is_read      BOOLEAN DEFAULT false,
  is_edited    BOOLEAN DEFAULT false,
  is_deleted   BOOLEAN DEFAULT false,
  read_at      TIMESTAMPTZ,
  edited_at    TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
)

-- File de notifications
notifications (
  id         UUID PRIMARY KEY,
  user_id    UUID REFERENCES users(id),
  type       TEXT NOT NULL,                          -- friend_request|remote_session_request|...
  payload    JSONB,
  is_read    BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
)
```

#### Sessions Distantes

```sql
-- Invitation de session (TTL 2 min)
remote_session_invites (
  id               UUID PRIMARY KEY,
  requester_id     UUID REFERENCES users(id),
  target_device_id TEXT NOT NULL,
  status           TEXT DEFAULT 'pending',           -- pending|accepted|rejected|expired
  session_token    TEXT,
  expires_at       TIMESTAMPTZ NOT NULL,             -- now() + 2 minutes
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
)

-- Session active
remote_sessions (
  id               UUID PRIMARY KEY,
  invite_id        UUID REFERENCES remote_session_invites(id),
  controller_id    UUID REFERENCES users(id),        -- initiateur (qui contrôle)
  host_id          UUID REFERENCES users(id),        -- cible (dont l'écran est partagé)
  host_device_id   TEXT,
  session_token    TEXT UNIQUE NOT NULL,             -- ULID unique
  session_type     TEXT,                             -- control|view_only|file_transfer|presentation
  quality          TEXT DEFAULT 'medium',            -- auto|low|medium|high|ultra
  encryption_type  TEXT DEFAULT 'aes256',
  started_at       TIMESTAMPTZ DEFAULT NOW(),
  ended_at         TIMESTAMPTZ,
  duration_seconds INT,
  end_reason       TEXT,                             -- host_ended|controller_ended|timeout|...
  bytes_sent       BIGINT DEFAULT 0,
  bytes_received   BIGINT DEFAULT 0,
  avg_latency_ms   INT,
  recorded         BOOLEAN DEFAULT false,
  recording_url    TEXT,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
)

-- Permissions granulaires par session
session_permissions (
  id                   UUID PRIMARY KEY,
  session_id           UUID UNIQUE REFERENCES remote_sessions(id),
  allow_keyboard       BOOLEAN DEFAULT true,
  allow_mouse          BOOLEAN DEFAULT true,
  allow_clipboard      BOOLEAN DEFAULT true,
  allow_file_transfer  BOOLEAN DEFAULT false,
  allow_audio          BOOLEAN DEFAULT false,
  allow_restart        BOOLEAN DEFAULT false,
  allow_lock_screen    BOOLEAN DEFAULT false,
  created_at           TIMESTAMPTZ DEFAULT NOW(),
  updated_at           TIMESTAMPTZ DEFAULT NOW()
)

-- Accès non supervisé (pré-autorisé)
unattended_access (
  id                    UUID PRIMARY KEY,
  host_user_id          UUID REFERENCES users(id),
  controller_user_id    UUID REFERENCES users(id),
  access_password_hash  TEXT,
  is_active             BOOLEAN DEFAULT true,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (host_user_id, controller_user_id)
)

-- Historique d'activité
activity_log (
  id               UUID PRIMARY KEY,
  user_id          UUID REFERENCES users(id),
  target_username  TEXT,
  target_device_id TEXT,
  session_type     TEXT,
  duration_seconds INT,
  status           TEXT,                             -- success|disconnected|failed
  started_at       TIMESTAMPTZ,
  ended_at         TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  INDEX (user_id, started_at DESC)
)
```

#### Communautés

```sql
-- Communauté
communities (
  id          UUID PRIMARY KEY,
  code        TEXT UNIQUE,                           -- code d'invitation 6-8 chars
  name        TEXT NOT NULL,
  description TEXT,
  country     TEXT,
  avatar_url  TEXT,
  owner_id    UUID REFERENCES users(id),
  is_public   BOOLEAN DEFAULT false,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  updated_at  TIMESTAMPTZ DEFAULT NOW(),
  deleted_at  TIMESTAMPTZ
)

-- Membre de communauté
community_members (
  id            UUID PRIMARY KEY,
  community_id  UUID REFERENCES communities(id),
  user_id       UUID REFERENCES users(id),
  department_id UUID REFERENCES departments(id),
  role          TEXT DEFAULT 'user',                 -- owner|admin|admin_sec|tech|user|viewer
  status        TEXT DEFAULT 'active',               -- active|suspended|banned
  joined_at     TIMESTAMPTZ DEFAULT NOW(),
  invited_by    UUID REFERENCES users(id),
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW(),
  deleted_at    TIMESTAMPTZ,
  UNIQUE (community_id, user_id)
)

-- Département (sous-groupe)
departments (
  id           UUID PRIMARY KEY,
  community_id UUID REFERENCES communities(id),
  name         TEXT NOT NULL,
  description  TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
)

-- Messages de communauté
community_messages (
  id           UUID PRIMARY KEY,
  community_id UUID REFERENCES communities(id),
  sender_id    UUID REFERENCES users(id),
  reply_to_id  UUID REFERENCES community_messages(id),
  content      TEXT NOT NULL,
  is_edited    BOOLEAN DEFAULT false,
  is_deleted   BOOLEAN DEFAULT false,
  edited_at    TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
)

-- Annonces épinglées
community_announcements (
  id           UUID PRIMARY KEY,
  community_id UUID REFERENCES communities(id),
  author_id    UUID REFERENCES users(id),
  title        TEXT NOT NULL,
  content      TEXT NOT NULL,
  is_pinned    BOOLEAN DEFAULT false,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW()
)

-- Demandes d'adhésion
join_requests (
  id           UUID PRIMARY KEY,
  community_id UUID REFERENCES communities(id),
  user_id      UUID REFERENCES users(id),
  message      TEXT,
  status       TEXT DEFAULT 'pending',               -- pending|approved|rejected
  reviewed_by  UUID REFERENCES users(id),
  reviewed_at  TIMESTAMPTZ,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (community_id, user_id)
)
```

#### Sécurité et Audit

```sql
-- Historique des connexions
login_history (
  id                 UUID PRIMARY KEY,
  user_id            UUID REFERENCES users(id),
  ip_address         TEXT,
  country            TEXT,
  city               TEXT,
  device_fingerprint TEXT,
  os                 TEXT,
  app_version        TEXT,
  status             TEXT,                           -- success|failed|blocked
  failure_reason     TEXT,
  created_at         TIMESTAMPTZ DEFAULT NOW()
)

-- Appareils de confiance
trusted_devices (
  id                 UUID PRIMARY KEY,
  user_id            UUID REFERENCES users(id),
  device_fingerprint TEXT,
  device_name        TEXT,
  last_used_at       TIMESTAMPTZ,
  trusted_at         TIMESTAMPTZ DEFAULT NOW(),
  revoked_at         TIMESTAMPTZ,
  created_at         TIMESTAMPTZ DEFAULT NOW(),
  updated_at         TIMESTAMPTZ DEFAULT NOW()
)

-- Journal d'audit système
audit_logs (
  id            UUID PRIMARY KEY,
  user_id       UUID REFERENCES users(id),
  action        TEXT NOT NULL,
  resource_type TEXT,
  resource_id   TEXT,
  ip_address    TEXT,
  user_agent    TEXT,
  metadata      JSONB,
  created_at    TIMESTAMPTZ DEFAULT NOW()
)
```

### 5.2 Diagramme entité-relation

```
┌──────────┐       ┌───────────────────┐       ┌────────────────────┐
│  users   │──────►│  device_sessions  │       │   refresh_tokens   │
│          │       │  (device_id)      │       │   (token_hash)     │
│  id      │◄──────┤  session_password │       │                    │
│  email   │  1:1  └───────────────────┘       └────────────────────┘
│  device_id│                                         ▲
└─────┬────┘                                         │ 1:N
      │ 1:N                                     ┌────┴──────┐
      │                                         │  users    │
      │ ┌─────────────────────────────────────► │           │
      │ │                                       └───────────┘
      ▼ │
┌─────────────┐  1:N  ┌───────────────────┐
│ friendships │       │  direct_messages  │
│  status:    │       │  sender_id        │
│  pending/   │       │  recipient_id     │
│  accepted/  │       │  content          │
│  blocked    │       └───────────────────┘
└─────────────┘

      │
      ▼
┌────────────────────┐  1:N  ┌────────────────────────┐
│  remote_session_   │──────►│  remote_sessions       │
│  invites           │       │  controller_id          │
│  requester_id      │       │  host_id                │
│  target_device_id  │       │  session_token (ULID)   │
│  status            │       │  session_type/quality   │
│  expires_at (2min) │       │  bytes_sent/received    │
└────────────────────┘       └──────────┬─────────────┘
                                        │ 1:1
                             ┌──────────▼─────────────┐
                             │  session_permissions    │
                             │  allow_keyboard         │
                             │  allow_mouse            │
                             │  allow_clipboard        │
                             │  allow_file_transfer    │
                             │  allow_audio            │
                             └────────────────────────┘

┌───────────────┐  1:N  ┌──────────────────┐  N:M  ┌────────┐
│  communities  │──────►│ community_members│◄──────│ users  │
│  code (invite)│       │ role             │       └────────┘
│  owner_id     │       │ status           │
│  is_public    │       └──────────────────┘
└───────┬───────┘
        │ 1:N
        ├──────────► community_messages
        ├──────────► community_announcements
        ├──────────► join_requests
        └──────────► departments
```

---

## 6. Architecture Client (Flutter)

### 6.1 Structure du projet

```
client/lib/
├── main.dart                          ← ProviderScope + runApp
│
├── app/
│   ├── app.dart                       ← MaterialApp + GoRouter + thème
│   ├── router.dart                    ← Routes + redirections GoRouter
│   │
│   ├── pages/                         ← Écrans principaux
│   │   ├── home_screen.dart           ← Dashboard contrôle à distance
│   │   ├── profile_screen.dart        ← Profil utilisateur
│   │   ├── settings_screen.dart       ← Paramètres (thème, langue)
│   │   ├── friends_screen.dart        ← Liste d'amis
│   │   ├── communities_screen.dart    ← Communautés
│   │   ├── notifications_screen.dart  ← Notifications
│   │   ├── messages_screen.dart       ← Conversations DM
│   │   └── auth/
│   │       ├── login_screen.dart
│   │       ├── register_wizard_screen.dart
│   │       ├── two_factor_screen.dart
│   │       ├── forgot_password_screen.dart
│   │       ├── reset_code_screen.dart
│   │       └── new_password_screen.dart
│   │
│   ├── state/                         ← Providers Riverpod
│   │   ├── auth_controller.dart       ← Machine à états auth
│   │   ├── data_providers.dart        ← Données API + état amis
│   │   ├── realtime_controller.dart   ← Événements WebSocket
│   │   ├── appearance_controller.dart ← Thème + locale
│   │   └── app_strings.dart           ← i18n (strings localisées)
│   │
│   └── widgets/                       ← Composants réutilisables
│       ├── app_shell.dart             ← Navigation shell (barre latérale)
│       ├── app_avatar.dart
│       ├── app_toast.dart
│       └── confirm_dialog.dart
│
├── screens/                           ← Implémentations détaillées
│   ├── remote_support_page.dart       ← Page session distante
│   ├── dm_screen.dart
│   ├── friends_screen.dart
│   ├── notifications_screen.dart
│   └── communities_screen.dart
│
├── services/                          ← Couche business logic
│   ├── api_client.dart                ← HTTP REST + gestion tokens
│   ├── ws_client.dart                 ← WebSocket + reconnexion
│   ├── signaling_client_service.dart  ← Protocole de signalisation
│   ├── auth_service.dart              ← Orchestration auth
│   ├── app_config.dart                ← Résolution URL API/WS
│   ├── remote_audio_service.dart
│   ├── file_transfer_service.dart
│   └── keyboard/
│       ├── keyboard_protocol.dart     ← Modèle événement clavier
│       ├── keyboard_state_manager.dart
│       ├── keyboard_transport.dart
│       ├── keyboard_layout_translator.dart
│       ├── keyboard_repeat_controller.dart
│       ├── keyboard_input_abstraction.dart
│       └── keyboard_host_injection_engine.dart
│
└── native/                            ← Bindings FFI natifs
    ├── vp9_codec.dart                 ← Encoder/Decoder VP9
    ├── dxgi_capturer.dart             ← Capture DXGI
    └── overlay_window.dart            ← Fenêtre overlay
```

### 6.2 Gestion d'état (Riverpod)

```
┌──────────────────────────────────────────────────────────────────────┐
│                     RIVERPOD PROVIDERS TREE                          │
└──────────────────────────────────────────────────────────────────────┘

apiClientProvider (Provider<ApiClient>)
  └─ Singleton HTTP client
  └─ Token management (secure storage + auto-refresh sur 401)

wsClientProvider (Provider<WsClient>)
  └─ Singleton WebSocket connection
  └─ Reconnexion avec backoff exponentiel (1s → 2s → 4s → ... max 15min)
  └─ Séparation: events stream (JSON) + binaryFrames stream (VP9)

wsEventsProvider (StreamProvider<Map<String,dynamic>>)
  └─ Dépend de: authControllerProvider (ne se connecte que si authentifié)
  └─ Expose les événements WebSocket au reste de l'app

authControllerProvider (StateNotifierProvider<AuthController, AuthState>)
  AuthState {
    stage:   signedOut | twoFactorRequired | signedIn
    user:    User?
    pendingTwoFactorToken: String?
  }
  Methods:
    login(identifier, password)
    register(username, email, password)
    verifyEmail(token)
    completeTwoFactor(code)
    logout()

friendsControllerProvider (StateNotifierProvider<FriendsController, FriendsState>)
  FriendsState {
    friends: List<Friend>    ← acceptés
    pending: List<Friend>    ← demandes reçues
    outgoing: List<Friend>   ← demandes envoyées
    blocked: List<Friend>
  }
  Methods:
    loadFriends()
    sendRequest(userId)
    acceptRequest(id)
    rejectRequest(id)
    removeFriend(userId)
    blockUser(userId)

realtimeControllerProvider (StateNotifierProvider<RealtimeController, RealtimeState>)
  └─ Écoute wsEventsProvider
  └─ Met à jour: messages, typing indicators, présence amis
  └─ Dispatch vers: FriendsController, DM screens

themeModeProvider (StateProvider<ThemeMode>)
localeProvider (StateProvider<Locale>)
```

#### Flux de données

```
Action utilisateur (UI)
         │
         ▼
StateNotifier.method()         ← ex: authController.login()
         │
         ▼
ApiClient.post(path, body)     ← HTTP + Bearer token
         │
    ┌────┴────┐
    │ 401?    │
    └────┬────┘
    Yes  │  No
    │    │
    ▼    ▼
refresh  Traiter réponse
token    │
    │    │
    └────┤
         ▼
Mise à jour State (StateNotifier.state = ...)
         │
         ▼
Riverpod notifie les ConsumerWidget dépendants
         │
         ▼
UI rebuilt (flutter rerender)
         │
         ◄────── WebSocket events → realtimeController → state update
```

### 6.3 Navigation (GoRouter)

```
/auth/login            ← Route initiale (non authentifié)
├─ /auth/register
├─ /auth/2fa           ← Si twoFactorRequired après login
├─ /auth/forgot
├─ /auth/reset-code
└─ /auth/new-password

/app                   ← ShellRoute avec AppShell (nav bar)
├─ /app/home           ← Dashboard contrôle à distance
├─ /app/profile
├─ /app/settings
├─ /app/messages
│  └─ /app/messages/:userId  ← Conversation DM
├─ /app/friends
├─ /app/communities
│  └─ /app/communities/:id   ← Détails communauté
└─ /app/notifications

Logique de redirection:
  Non authentifié          → /auth/login
  2FA en attente           → /auth/2fa
  Authentifié              → /app/home
```

---

## 7. Flux d'Authentification et Sécurité

### Inscription et Connexion

```
┌────────────────────────────────────────────────────────────────────┐
│  INSCRIPTION                                                       │
└────────────────────────────────────────────────────────────────────┘

POST /auth/register {username, email, password}
      │
      ▼
Server:
  ├─ Hash password → bcrypt(cost=12)
  ├─ Générer device_id = SHA256(email + uuid4)
  ├─ Créer user (is_verified=true, auto-verified)
  ├─ Créer device_session {device_id, session_password: randint(6)}
  ├─ Générer access_token (JWT HS256, exp: +15min)
  │   Claims: {sub: userID, device_id, role, iat, exp}
  ├─ Générer refresh_token (JWT HS256, exp: +7 jours)
  │   └─ Hash → stocker en DB (refresh_tokens)
  └─ Retourner 201 {access_token, refresh_token, user}

┌────────────────────────────────────────────────────────────────────┐
│  CONNEXION                                                         │
└────────────────────────────────────────────────────────────────────┘

POST /auth/login {identifier, password, device_fingerprint?}
      │
      ▼
Server:
  ├─ Lookup user par username ou email
  ├─ Vérifier bcrypt(password, password_hash)
  ├─ Vérifier locked_until (protection brute force)
  ├─ Si 2FA activé:
  │   ├─ Générer temp_token (JWT, exp: +5min)
  │   └─ Retourner 200 {requires_2fa: true, temp_token}
  │
  └─ Si pas de 2FA:
      ├─ Générer access_token + refresh_token
      ├─ Enregistrer login_history (IP, pays, device_fingerprint, status: success)
      ├─ Réinitialiser failed_login_count
      └─ Retourner 200 {access_token, refresh_token, user}

┌────────────────────────────────────────────────────────────────────┐
│  CHALLENGE 2FA (TOTP)                                              │
└────────────────────────────────────────────────────────────────────┘

POST /auth/2fa/challenge {temp_token, code}
      │
      ▼
Server:
  ├─ Valider temp_token (JWT, non expiré)
  ├─ Extraire userID depuis le subject du temp_token
  ├─ Récupérer two_factor_secret (déchiffrer AES)
  ├─ Vérifier TOTP: HMAC-SHA1, fenêtre 30s, 6 chiffres
  ├─ Si invalide: 400 Bad Request
  └─ Si valide:
      ├─ Générer access_token + refresh_token
      └─ Retourner 200 {access_token, refresh_token, user}

┌────────────────────────────────────────────────────────────────────┐
│  REFRESH TOKEN                                                     │
└────────────────────────────────────────────────────────────────────┘

POST /auth/refresh {refresh_token}
      │
      ▼
Server:
  ├─ Hash(refresh_token) → lookup en DB
  ├─ Vérifier revoked_at IS NULL
  ├─ Vérifier expires_at > NOW()
  ├─ Générer nouveau access_token
  └─ Retourner 200 {access_token}

Client (ApiClient):
  ├─ Appel API → 401 Unauthorized
  ├─ Appel _refreshAccessToken()
  ├─ Sauvegarder nouveau access_token (FlutterSecureStorage)
  └─ Relancer la requête initiale
```

### Stockage des tokens côté client

```
Token Storage (priorité):
  1. FlutterSecureStorage  ← Keychain/Keystore plateforme
  2. SharedPreferences     ← Fallback si secure storage indisponible

Clés: 'access_token', 'refresh_token'

Au démarrage (AuthController._bootstrap()):
  ├─ Lire tokens depuis secure storage
  ├─ Si access_token présent → charger profil user (GET /users/me)
  ├─ Si réussi → state.stage = signedIn
  └─ Si échoue → essayer refresh → si réussi → signedIn, sinon signedOut
```

---

## 8. Pipeline de Contrôle à Distance

### 8.1 Flux d'invitation

```
┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 1 — INVITATION                                               │
└─────────────────────────────────────────────────────────────────────┘

Contrôleur (Client A)
      │
      ├─ POST /remote/invite/{target_device_id}
      │   body: {session_password?: "123456"}  (optionnel)
      │
      └─→ Serveur:
          ├─ Vérifier amitié ou appartenance même communauté
          ├─ Si session_password: comparer avec device_session.session_password
          ├─ Créer RemoteSessionInvite {
          │    requester_id, target_device_id,
          │    status: "pending",
          │    expires_at: NOW() + INTERVAL '2 minutes'
          │  }
          ├─ Broadcast WebSocket à la cible:
          │   {type: "remote:invite", payload: {invite_id, requester_id, expires_at}}
          ├─ Créer notification en DB
          └─ Retourner 201 {invite}

Cible (Client B):
  ├─ Reçoit événement "remote:invite" via WS
  └─ Affiche pop-up: "User A veut contrôler votre écran"

┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 2 — ACCEPTATION / REFUS                                      │
└─────────────────────────────────────────────────────────────────────┘

Cible répond:
      │
      ├─ PATCH /remote/invite/{invite_id} {action: "accept" | "reject"}
      │
      └─→ Serveur:
          ├─ Si "reject":
          │   ├─ Update status → "rejected"
          │   └─ Broadcast "remote:invite_rejected" au contrôleur
          │
          └─ Si "accept":
              ├─ Update status → "accepted"
              ├─ Générer session_token (ULID)
              └─ Retourner invite avec session_token

┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 3 — CRÉATION DE SESSION                                      │
└─────────────────────────────────────────────────────────────────────┘

Contrôleur crée la session:
      │
      ├─ POST /remote/sessions {
      │    host_user_id, host_device_id,
      │    invite_id, session_type: "control",
      │    quality: "medium", session_token
      │  }
      │
      └─→ Serveur:
          ├─ Vérifier invite: status=accepted, non expiré
          ├─ Créer RemoteSession {
          │    controller_id, host_id, host_device_id,
          │    session_token, session_type, quality,
          │    encryption_type: "aes256"
          │  }
          ├─ Créer SessionPermissions (defaults: keyboard+mouse+clipboard on)
          ├─ Broadcast "remote:session_started" aux deux peers
          └─ Retourner 201 {session}

┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 4 — CONNEXION PEER-TO-PEER (via WebSocket serveur)           │
└─────────────────────────────────────────────────────────────────────┘

Contrôleur:
  GET /api/v1/ws?token=<JWT>&client_id=<ID>
  └─ Envoie: {type: "register", sessionId, role: "controller"}

Hôte:
  GET /api/v1/ws?token=<JWT>&client_id=<ID>
  └─ Envoie: {type: "register", sessionId, role: "host"}

Serveur:
  ├─ Enregistre les deux connexions dans clientRegistry
  └─ Lie les connexions par sessionId

┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 5 — STREAMING                                                │
└─────────────────────────────────────────────────────────────────────┘

[Voir section 8.2 — Pipeline vidéo VP9]

┌─────────────────────────────────────────────────────────────────────┐
│  PHASE 6 — FIN DE SESSION                                           │
└─────────────────────────────────────────────────────────────────────┘

Fermeture WebSocket (l'un ou l'autre peer):
      │
      └─→ Serveur readLoop() déclencheur cleanup:
          ├─ Repo.EndRemoteSession(sessionID, reason, endedAt)
          ├─ Mettre à jour ActivityLog (durée, bytes, raison)
          └─ Broadcast "remote:session_ended" aux deux peers
```

### 8.2 Pipeline vidéo VP9

```
┌──────────────────────────────────────────────────────────────────────┐
│                    PIPELINE VIDÉO COMPLET                            │
└──────────────────────────────────────────────────────────────────────┘

CÔTÉ HÔTE (Client B — partageur d'écran)
─────────────────────────────────────────

  Boucle capture (30-60 FPS)
       │
       ▼
  DxgiCapturer.captureFrame()           ← ~1-3 ms/frame
       │  IDXGIOutputDuplication.AcquireNextFrame()
       │  GetDesktopImage() → texture DXGI
       │  Map en mémoire CPU → BGRA pixels
       │
       ▼
  Vp9Encoder.encode(bgraPixels, forceKeyframe?)
       │  FFI → bim_encoder_create(width, height, bitrateKbps)
       │  Encode BGRA → VP9 bitstream (hardware accéléré si dispo)
       │  CBR mode: 500-5000 kbps selon qualité
       │
       ▼
  Enveloppe binaire:
  [0xB1][0x4D][ver 2B][toIDLen 4B][toClientID N B][VP9 payload]
       │
       ▼
  WebSocket.sink.add(binaryData)        ← envoi binaire

CÔTÉ SERVEUR — ROUTAGE
───────────────────────

  WS.ReadMessage() → binary frame
       │
       ▼
  handleBinaryVideoFrame(msg)
       ├─ Lire magic bytes [0xB1, 0x4D]
       ├─ Lire toIDLen = uint32 LE [4:8]
       ├─ Extraire toClientID = msg[8 : 8+toIDLen]
       ├─ Chercher conn dans clientRegistry[toClientID]
       └─ conn.Send <- msg  (non-bloquant, drop si buffer plein 256)

CÔTÉ CONTRÔLEUR (Client A — viewer)
─────────────────────────────────────

  WsClient.binaryFrames stream
       │
       ▼
  Vp9Decoder.decode(vp9Packet)          ← ~5 ms/frame
       │  FFI → bim_decoder_create()
       │  Décode VP9 → BGRA pixels
       │  Redimensionne buffer si résolution change
       │
       ▼
  Rendu Flutter (canvas / texture)
       │
       └─ Affichage à 60 FPS cible

PIPELINE D'INPUT (Controller → Host)
──────────────────────────────────────

  Clavier / Souris capturés sur le Contrôleur
       │
       ▼
  KeyboardKeyEvent {
    physicalCode, logicalKeyId, characterCodePoint,
    phase: "down"|"up",
    modifiers: {shift, ctrl, alt, meta, capsLock, numLock},
    clientLayout: "fr-FR",
    clientLayoutFamily: "AZERTY",
    sequenceNumber, captureTimestampMs
  }
       │
       ▼
  Envoi WebSocket JSON:
  {type: "keyboard:input", sessionId, event: KeyboardKeyEvent}
       │
       ▼
  Serveur → Relay vers l'Hôte
       │
       ▼
  Hôte reçoit événement
       ├─ Vérifier session_permissions.allow_keyboard
       ├─ KeyboardHostInjectionEngine.inject(event)
       │   └─ Traduire layout: AZERTY → QWERTY si nécessaire
       │   └─ Win32 SendInput(INPUT_KEYBOARD, ...)
       └─ Continuer boucle capture

  Souris: throttle 60 Hz, {x, y, buttons} → Win32 SendInput(INPUT_MOUSE)
```

### 8.3 Couche native (Rust FFI)

```
bimstreaming_codec.dll (Rust)
──────────────────────────────

Exports FFI utilisés par Dart:
  bim_encoder_create(width: u32, height: u32, bitrate_kbps: u32) → *mut Encoder
  bim_encoder_encode(enc: *mut Encoder, bgra: *const u8, force_key: bool,
                     out: *mut u8, out_len: *mut usize) → i32
  bim_encoder_destroy(enc: *mut Encoder)

  bim_decoder_create() → *mut Decoder
  bim_decoder_decode(dec: *mut Decoder, data: *const u8, len: usize,
                     out: *mut u8, out_len: *mut usize,
                     w: *mut u32, h: *mut u32) → i32
  bim_decoder_destroy(dec: *mut Decoder)

DxgiCapturer (Windows DirectX 11):
  ├─ IDXGIFactory1.EnumAdapters()       ← Enumérer les GPUs
  ├─ IDXGIOutput.DuplicateOutput()      ← Dupliquer la sortie display
  ├─ AcquireNextFrame(timeout=16ms)     ← Attendre un nouveau frame
  ├─ GetDesktopImage() → ID3D11Texture2D
  ├─ Map(CPU_READ) → pointeur BGRA
  └─ ReleaseFrame()

Avantage DXGI vs GDI:
  DXGI: ~1-3 ms/frame, hardware-accéléré, résolution native
  GDI BitBlt: ~15-20 ms/frame, CPU only, plus lent
```

---

## 9. Architecture de Messagerie en Temps Réel

```
┌──────────────────────────────────────────────────────────────────────┐
│  WEBSOCKET HUB — DIFFUSION DE PRÉSENCE                               │
└──────────────────────────────────────────────────────────────────────┘

Utilisateur se connecte:
      │
      ▼
Router.HandleWS()
  ├─ Upgrade HTTP → WebSocket
  ├─ Valider JWT token
  ├─ Créer Client{ID, Conn, Send chan (buffer 256)}
  ├─ Hub.Register(userID, conn)
  ├─ readLoop(client)    ─── goroutine
  └─ writeLoop(client)   ─── goroutine

setPresenceAndBroadcast(userID, isOnline=true):
  ├─ Repo.SetOnlineStatus(userID, true)
  ├─ Repo.ListAcceptedFriendIDs(userID)
  │   SELECT id FROM friendships WHERE
  │     (requester_id=userID OR addressee_id=userID)
  │     AND status='accepted'
  ├─ targets = [userID] + friendIDs
  └─ Hub.PublishToMany(targets, "user:online", {user_id: userID})

Hub.PublishToMany(userIDs, eventType, payload):
  ├─ mu.RLock()
  ├─ Pour chaque userID dans userIDs:
  │   ├─ Chercher connections[userID]
  │   └─ Pour chaque conn:
  │       ├─ Marshal: {type: eventType, payload: payload}
  │       └─ conn.Send <- jsonMsg  (non-bloquant)
  └─ mu.RUnlock()

Client Côté Flutter:
  wsEventsProvider reçoit {type: "user:online", payload: {user_id}}
       │
       ▼
  realtimeController:
  ├─ FriendsController.markOnline(userId)
  └─ UI rebuild: badge vert sur l'avatar

┌──────────────────────────────────────────────────────────────────────┐
│  MESSAGES DIRECTS — ENVOI ET RÉCEPTION                               │
└──────────────────────────────────────────────────────────────────────┘

Envoi message:
  POST /dm/{userId} {content: "Hello"}
       │
       ▼
  Serveur:
  ├─ Créer direct_message {sender_id, recipient_id, content}
  ├─ Créer notification {user_id: recipient, type: "dm", payload: {...}}
  ├─ Hub.PublishToUser(recipient_id, "dm:new_message", {
  │    sender_id, content, created_at, conversation_id
  │  })
  └─ Si Push FCM configuré: envoyer notification push

Réception temps réel côté Flutter:
  wsEventsProvider → {type: "dm:new_message", payload: {...}}
       │
       ▼
  realtimeController:
  ├─ Mettre à jour messages en cache
  └─ Si DmScreen ouverte: ajouter message à la liste
```

---

## 10. Architecture de Sécurité

```
┌─────────────────────────────────────────────────────────────────────┐
│  COUCHES DE SÉCURITÉ                                                │
└─────────────────────────────────────────────────────────────────────┘

1. TRANSPORT
   ├─ HTTPS / WSS (TLS 1.2+) pour toutes les communications
   └─ JWT Bearer token dans header Authorization

2. AUTHENTIFICATION
   ├─ Passwords: bcrypt (cost 12)
   ├─ JWT: HS256, access_token 15min, refresh_token 7j
   ├─ 2FA: TOTP (RFC 6238), HMAC-SHA1, 30s, 6 chiffres
   ├─ Backup codes: 8 codes SHA256-hachés
   └─ Brute force: lock 15min après N échecs (failed_login_count)

3. AUTORISATION
   ├─ Toute route /api/v1 (sauf /auth/*): RequireAuth middleware
   ├─ JWT claims: userID, deviceID, role
   ├─ Rôles par communauté: owner > admin > admin_sec > tech > user > viewer
   └─ Permissions par session: allow_keyboard/mouse/clipboard/audio/...

4. CHIFFREMENT DONNÉES
   ├─ Mots de passe: bcrypt (irréversible)
   ├─ Secrets TOTP: chiffrés AES-256 en DB
   ├─ Refresh tokens: hachés SHA-256 en DB
   ├─ Connexions de session distante: encryption_type = "aes256"
   └─ Tokens client: FlutterSecureStorage (Keychain iOS, Keystore Android/Win)

5. RATE LIMITING
   ├─ Global: 200 req/min par IP
   ├─ Auth endpoints: 10 req/min par IP
   └─ Réponse: 429 Too Many Requests

6. AUDIT
   ├─ login_history: toutes les tentatives (succès, échec, bloqué)
   ├─ audit_logs: actions sensibles (ban, delete, permissions)
   └─ activity_log: sessions distantes (durée, bytes, raison fin)

┌─────────────────────────────────────────────────────────────────────┐
│  CONTRÔLE D'ACCÈS SESSION DISTANTE                                  │
└─────────────────────────────────────────────────────────────────────┘

Conditions pour créer une invitation:
  ├─ Être amis (status: accepted dans friendships)
  │  OU être membres de la même communauté
  ├─ Optionnel: connaître le session_password de l'appareil cible
  └─ Invitation expire après 2 minutes

Types de session:
  control        ← Accès clavier + souris + presse-papiers
  view_only      ← Vue seule, aucun input
  file_transfer  ← Transfert fichiers uniquement
  presentation   ← Faible latence, pas d'input

Permissions granulaires (par défaut):
  allow_keyboard     = true
  allow_mouse        = true
  allow_clipboard    = true
  allow_file_transfer = false
  allow_audio        = false
  allow_restart      = false
  allow_lock_screen  = false
```

---

## 11. Performances et Optimisations

```
┌──────────────────────────────────────────────────────────────────────┐
│  PERFORMANCE PAR COUCHE                                              │
└──────────────────────────────────────────────────────────────────────┘

CAPTURE ÉCRAN
  ├─ DXGI Desktop Duplication: 1-3 ms/frame
  │   Accélération DirectX 11, capture native GPU
  └─ Fallback GDI BitBlt: 15-20 ms/frame (moins performant)

CODEC VP9
  ├─ Hardware encoding: NVENC (NVIDIA), Quick Sync (Intel) si disponible
  ├─ CBR (Constant Bitrate) pour prédictibilité réseau
  ├─ Keyframe injection à la demande (qualité → changement)
  └─ Bitrates configurables:
       auto   → 1000-5000 kbps adaptatif
       low    → 500 kbps
       medium → 1500 kbps (défaut)
       high   → 3000 kbps
       ultra  → 5000+ kbps

RÉSEAU WEBSOCKET
  ├─ Frames binaires pour vidéo (pas de surcoût JSON)
  ├─ Text JSON seulement pour signalisation
  ├─ Buffer send par client: 256 messages (drop si plein)
  └─ Reconnexion: backoff exponentiel 1s → 2s → 4s → ... max 15min

BASE DE DONNÉES
  ├─ Pool de connexions: 25 ouvertes + 25 idle, timeout 5min
  ├─ Index sur colonnes fréquentes: device_id, user_id, created_at
  ├─ Statements préparés via sqlx
  └─ Pagination curseur (limit 50) pour listes

CLIENT FLUTTER
  ├─ Riverpod: rebuilds ciblés (pas de setState global)
  ├─ GoRouter: lazy loading des routes
  ├─ Tokens: chargement asynchrone au démarrage
  └─ WebSocket: un seul singleton, toutes les features partagent la connexion

OBJECTIFS DE PERFORMANCE
  Latence clavier/souris:  < 20 ms (LAN)
  FPS vidéo:               30-60 FPS (dépend réseau)
  Démarrage session:        < 3 secondes (invite → streaming)
  Reconnexion WS:           < 2 secondes (réseau stable)
```

---

*Document généré à partir de l'analyse du code source BimStreaming. Version: mai 2026.*
