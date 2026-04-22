# BimStreaming

Architecture refactorisee en **client/server strict**.

- `server/`: backend Go relay-only (WebSocket/TCP transport, sessions, routage client->client)
- `client/`: application Flutter Windows (UI, capture ecran, envoi/reception des commandes)

## Structure

- `server/main.go`: bootstrap HTTP + WS (`/api/v1/ws`) + health (`/healthz`)
- `server/router.go`: upgrade WebSocket, relay des messages, pairage de session
- `server/clients.go`: registre des clients connectes
- `server/sessions.go`: registre des sessions de controle
- `client/lib/main.dart`: entree Flutter
- `client/lib/network`: couche reseau client
- `client/lib/screen`: couche capture/stream
- `client/lib/input`: couche input
- `client/lib/ui`: couche UI

## Demarrage rapide

### 1) Lancer le serveur

```powershell
Set-Location server
go run .
```

Option: `SERVER_ADDR` (defaut `:8080`)

### 2) Lancer le client

```powershell
Set-Location client
flutter run -d windows --dart-define=BIM_SIGNAL_URL=ws://YOUR_PUBLIC_IP:8080/api/v1/ws
```

## Script unifie

Depuis la racine:

```powershell
.\start-dev.ps1 -SignalUrl ws://YOUR_PUBLIC_IP:8080/api/v1/ws
```

Le script demarre le serveur (`server/`) puis lance Flutter depuis `client/`.

## Backend et migrations

Le serveur Go expose l'API HTTP sous `/api/v1` et conserve le canal WebSocket existant pour le routage temps reel.

### Variables d'environnement serveur

- `DATABASE_URL=postgres://user:pass@host:5432/bim_streaming?sslmode=require`
- `JWT_SECRET=<32-byte hex>`
- `JWT_REFRESH_SECRET=<32-byte hex>`
- `ENCRYPTION_KEY=<32-byte hex>`
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `SMTP_FROM`
- `APP_BASE_URL=https://app.bim-streaming.com`
- `AVATAR_STORAGE_PATH=./storage/avatars`
- `MAX_UPLOAD_SIZE_MB=5`
- `RATE_LIMIT_ENABLED=true`

### Lancer les migrations

Avec `golang-migrate` installe, depuis la racine du repo:

```powershell
migrate -path .\server\migrations -database "$env:DATABASE_URL" up
```

Pour revenir en arriere:

```powershell
migrate -path .\server\migrations -database "$env:DATABASE_URL" down 1
```

### Demarrer le serveur

```powershell
Set-Location server
go run .
```

Le serveur ecoute par defaut sur `:8080` et expose:

- `GET /healthz`
- `GET /api/v1/ws?token=<access_token>`
- les routes REST `GET/POST/PATCH/DELETE` sous `/api/v1`

La specification OpenAPI se trouve dans [server/openapi.yaml](server/openapi.yaml).

## Rapport de migration

Voir `ARCHITECTURE_SPLIT_REPORT.md` pour le detail des deplacements et de la compatibilite protocole.
