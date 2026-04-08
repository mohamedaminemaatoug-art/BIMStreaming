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

## Rapport de migration

Voir `ARCHITECTURE_SPLIT_REPORT.md` pour le detail des deplacements et de la compatibilite protocole.
