# BIMStreaming Backend Architecture (Production-Grade)

## 1. Architecture globale

Le backend suit une architecture en couches et orientee domaines:
- API HTTP + WebSocket sur Go.
- PostgreSQL pour les donnees persistantes.
- Redis pour presence, etat temps reel et diffusion inter-instances.
- Keycloak pour OIDC/OAuth2 et validation JWT.
- coturn pour STUN/TURN (NAT traversal).
- Prometheus + Grafana pour observabilite.

Flux principal:
1. Client Flutter s'authentifie via Keycloak, recupere JWT.
2. Le backend valide JWT (issuer/audience/jwks).
3. Le device se declare en ligne (PostgreSQL + Redis TTL).
4. Le signaling WebSocket route les messages de session.
5. Les sessions sont creees/maj en PostgreSQL.
6. Les metriques sont exposees sur /metrics.

## 2. Responsabilite des couches

- cmd/: point d'entree, wiring de l'application, bootstrap infra.
- internal/config/: configuration centralisee via variables d'environnement.
- internal/models/: entites GORM (Device, Session).
- internal/repository/: acces donnees PostgreSQL.
- internal/service/: logique metier (device, presence, session, ICE).
- internal/handler/: couche transport HTTP/WebSocket.
- internal/websocket/: hub de connexions et routage signaling.
- internal/middleware/: JWT OIDC, rate limiting, securite transversale.
- pkg/: utilitaires partageables (logger, metrics).
- deploy/: Docker, Compose, coturn, Prometheus.

## 3. Securite

- Validation JWT via JWKS Keycloak.
- Verification issuer + audience.
- Middleware protecteur sur /api/v1/*.
- Rate limit sur API.
- Input validation JSON et erreurs normalisees.
- Graceful shutdown pour eviter les sessions coupees brutalement.
- Ready pour HTTPS/WSS via reverse proxy (Traefik/Nginx).

## 4. Endpoints principaux

- GET /healthz
- GET /metrics
- GET /api/v1/ws?user_id=<id>
- POST /api/v1/devices/register
- POST /api/v1/sessions/create
- POST /api/v1/sessions/accept
- POST /api/v1/sessions/reject
- POST /api/v1/sessions/end
- GET /api/v1/ice-servers

## 5. Messages signaling routes

- connection_request
- connection_accept
- connection_reject
- ice_candidate
- session_end

Le hub WebSocket route via la map locale et publie aussi un event Redis (base de scaling horizontal).

## 6. Installation des packages necessaires

Prerequis locaux:
- Go 1.22+
- Docker + Docker Compose

Packages Go:
```bash
cd backend/signaling-go
go mod tidy
```

Services infra:
```bash
cd deploy/docker
docker compose up -d --build
```

## 7. Run backend

```bash
cd backend/signaling-go
cp .env.example .env
# adapter les variables si besoin

go run ./cmd/server
```

## 8. Monitoring

- Prometheus scrape: deploy/prometheus/prometheus.yml
- Grafana: http://localhost:3000
- Prometheus: http://localhost:9090

Metriques exposees:
- bim_ws_connections
- bim_online_devices
- bim_active_sessions
- bim_http_errors_total{route}

## 9. coturn integration

Fichier: deploy/coturn/turnserver.conf

Le backend expose GET /api/v1/ice-servers et retourne STUN + TURN credentials.

## 10. Niveau PFE / defendable

Points defendables academiquement:
- Separation claire des couches et responsabilites.
- Choix techno alignes systeme distribue temps reel.
- Presence TTL Redis pour resilence aux deconnexions abruptes.
- Tracking sessions complet en base relationnelle.
- Observabilite native et securite OIDC standard.
- Ready for scale-out avec pub/sub Redis et stateless HTTP.
