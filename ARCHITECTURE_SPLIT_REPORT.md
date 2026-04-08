# Architecture Split Report

## Nouveau layout

- `server/` : backend Go relay only
  - `server/main.go` : boot serveur HTTP + WebSocket (`/api/v1/ws`) + health check
  - `server/router.go` : upgrade WS, routage des messages, pairage session A<->B, relay brut
  - `server/clients.go` : registre thread-safe des clients connectes
  - `server/sessions.go` : registre thread-safe des sessions de controle
- `client/` : application Flutter autonome
  - `client/lib/main.dart` : point d'entree Flutter (copie fonctionnelle)
  - `client/lib/network/` : facade reseau
  - `client/lib/screen/` : facade capture/streaming
  - `client/lib/input/` : facade input keyboard/mouse
  - `client/lib/ui/` : facade UI

## Ce qui a ete deplace

- Flutter app complete copiee vers `client/` (sources + windows runner + pubspec).
- Logique WebSocket client conservee dans `client/lib/services/signaling_client_service.dart`.
- Endpoint fallback client mis a jour vers `ws://SERVER_PUBLIC_IP:8080/api/v1/ws` (override possible via `BIM_SIGNAL_URL`).

## Ce qui a ete reecrit

- Nouveau backend Go minimal relay dans `server/`:
  - ne capture pas d'ecran
  - n'injecte pas clavier/souris
  - ne contient aucune logique UI
  - ne parse pas/metier les payloads de controle: il route uniquement
- Pairage session maintenu par `session_id` + `from/to` pour relayer `connection_request`, `connection_accept/reject`, `session_message`.

## Separation des responsabilites

- **Server**: transport TCP/WS, gestion connexions, pairage, relay.
- **Client**: capture ecran, envoi stream, reception commandes, injection locale, UI.

## Compatibilite protocole

- Le format des messages WS deja utilise par le client est conserve:
  - `connection_request`, `connection_accept`, `connection_reject`, `session_message`
  - payload interne inchange, relay brut.

## Validation executee

- `go build ./...` dans `server/` : OK
- `flutter analyze lib/services/signaling_client_service.dart` dans `client/` : OK

## Execution

### Server

```powershell
Set-Location server
go run .
```

Variable optionnelle:

- `SERVER_ADDR` (defaut `:8080`)

### Client

```powershell
Set-Location client
flutter run -d windows --dart-define=BIM_SIGNAL_URL=ws://YOUR_PUBLIC_IP:8080/api/v1/ws
```

## Notes de migration

- Le nouveau split est operationnel dans `server/` + `client/`.
- Nettoyage final applique: suppression des anciens repertoires executables racine (`backend/`, `build/`, `lib/`, `windows/`, `pubspec.yaml`, `pubspec.lock`).
