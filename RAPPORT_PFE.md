# BimStreaming — Rapport Technique de Projet de Fin d'Études

> Document de référence technique destiné à la rédaction d'un rapport de stage de fin d'études (PFE).
> Version : 1.2.0 — Date : Mai 2026

---

## Table des matières

1. [Introduction](#1-introduction)
   - 1.1 [Contexte du projet](#11-contexte-du-projet)
   - 1.2 [Problématique](#12-problématique)
   - 1.3 [Objectifs](#13-objectifs)
   - 1.4 [Périmètre et limites](#14-périmètre-et-limites)

2. [Vue d'ensemble du système](#2-vue-densemble-du-système)
   - 2.1 [Description générale](#21-description-générale)
   - 2.2 [Fonctionnalités principales](#22-fonctionnalités-principales)
   - 2.3 [Utilisateurs cibles](#23-utilisateurs-cibles)

3. [Architecture du système](#3-architecture-du-système)
   - 3.1 [Type d'architecture](#31-type-darchitecture)
   - 3.2 [Description des composants](#32-description-des-composants)
   - 3.3 [Flux de données entre les composants](#33-flux-de-données-entre-les-composants)
   - 3.4 [Diagramme d'architecture](#34-diagramme-darchitecture)

4. [Frontend — Application cliente Flutter](#4-frontend--application-cliente-flutter)
   - 4.1 [Technologies utilisées](#41-technologies-utilisées)
   - 4.2 [Structure du projet](#42-structure-du-projet)
   - 4.3 [Pages et composants principaux](#43-pages-et-composants-principaux)
   - 4.4 [Gestion d'état](#44-gestion-détat)
   - 4.5 [Logique UI/UX](#45-logique-uiux)
   - 4.6 [Communication avec le backend](#46-communication-avec-le-backend)

5. [Backend — Serveur Go](#5-backend--serveur-go)
   - 5.1 [Technologies utilisées](#51-technologies-utilisées)
   - 5.2 [Architecture logicielle](#52-architecture-logicielle)
   - 5.3 [Conception des API REST](#53-conception-des-api-rest)
   - 5.4 [Modules et services principaux](#54-modules-et-services-principaux)
   - 5.5 [Authentification et autorisation](#55-authentification-et-autorisation)
   - 5.6 [Logique métier](#56-logique-métier)

6. [Conception de la base de données](#6-conception-de-la-base-de-données)
   - 6.1 [Système de gestion choisi](#61-système-de-gestion-choisi)
   - 6.2 [Description des tables](#62-description-des-tables)
   - 6.3 [Relations entre entités](#63-relations-entre-entités)
   - 6.4 [Contraintes et indexation](#64-contraintes-et-indexation)
   - 6.5 [Diagramme Entité-Relation](#65-diagramme-entité-relation)

7. [Serveur et déploiement](#7-serveur-et-déploiement)
   - 7.1 [Rôle du serveur](#71-rôle-du-serveur)
   - 7.2 [Environnement et configuration](#72-environnement-et-configuration)
   - 7.3 [Processus de déploiement](#73-processus-de-déploiement)
   - 7.4 [Considérations de performance](#74-considérations-de-performance)

8. [Cas d'utilisation et workflows principaux](#8-cas-dutilisation-et-workflows-principaux)
   - 8.1 [Authentification et connexion](#81-authentification-et-connexion)
   - 8.2 [Établissement d'une session de contrôle à distance](#82-établissement-dune-session-de-contrôle-à-distance)
   - 8.3 [Messagerie en temps réel](#83-messagerie-en-temps-réel)

9. [Défis techniques et solutions](#9-défis-techniques-et-solutions)

10. [Sécurité](#10-sécurité)
    - 10.1 [Protection des données](#101-protection-des-données)
    - 10.2 [Mécanismes d'authentification](#102-mécanismes-dauthentification)
    - 10.3 [Vulnérabilités traitées](#103-vulnérabilités-traitées)

11. [Optimisation des performances](#11-optimisation-des-performances)

12. [Tests](#12-tests)

13. [Améliorations futures](#13-améliorations-futures)

14. [Conclusion](#14-conclusion)

---

## 1. Introduction

### 1.1 Contexte du projet

BimStreaming est une application de bureau Windows développée dans le cadre d'un projet de stage de fin d'études. Le projet s'inscrit dans un contexte professionnel où les équipes techniques dispersées géographiquement ont besoin d'outils de collaboration et de support à distance performants, sécurisés et intégrés.

Face à la prolifération des solutions de contrôle à distance (TeamViewer, AnyDesk, Microsoft Remote Desktop) et des plateformes de collaboration (Slack, Discord, Microsoft Teams), BimStreaming se positionne comme une solution hybride combinant ces deux cas d'usage au sein d'une application unifiée, conçue pour les environnements d'entreprise avec des exigences en matière de souveraineté des données et de conformité RGPD.

### 1.2 Problématique

Les équipes techniques font face à plusieurs problèmes distincts avec les outils existants :

- **Fragmentation des outils** : les agents de support utilisent simultanément un outil de contrôle à distance et une plateforme de messagerie, entraînant une perte de contexte et de productivité.
- **Dépendance aux services tiers** : les solutions SaaS de contrôle à distance transmettent les flux vidéo via des infrastructures tierces, soulevant des questions de confidentialité.
- **Absence de gestion communautaire** : les outils existants ne permettent pas d'organiser les utilisateurs en communautés hiérarchiques avec des rôles et des départements.
- **Latence élevée** : les solutions grand public ne sont pas optimisées pour le contrôle à distance à haute fréquence d'images (30–60 fps) sur des réseaux locaux d'entreprise.

### 1.3 Objectifs

Les objectifs du projet sont les suivants :

1. Développer une application de bureau Windows offrant le contrôle à distance en temps réel avec capture d'écran à 30–60 fps.
2. Implémenter un système de messagerie directe et communautaire avec présence en temps réel.
3. Concevoir une architecture client-serveur où le serveur agit comme un relais transparent, sans traitement des données de session.
4. Garantir la sécurité des communications via JWT, chiffrement AES-256 et authentification à deux facteurs (TOTP).
5. Assurer la conformité RGPD avec export de données et suppression de compte.
6. Fournir un système de plans d'abonnement avec application de quotas.

### 1.4 Périmètre et limites

**Dans le périmètre :**
- Application desktop Windows uniquement (Flutter Windows target)
- Contrôle à distance via relais WebSocket (pas de connexion peer-to-peer directe)
- Authentification locale (pas d'OAuth tiers)
- Stockage local des avatars et pièces jointes (pas d'objet storage cloud)

**Hors périmètre :**
- Applications mobiles (iOS, Android)
- Application web
- Connexion peer-to-peer (WebRTC)
- Paiement en ligne intégré (le système de plans est présent mais le module de paiement est hors scope)

---

## 2. Vue d'ensemble du système

### 2.1 Description générale

BimStreaming est une application de bureau Windows full-stack composée de deux parties distinctes :

- **Le client Flutter** : une application Windows construite avec le framework Flutter, responsable de l'ensemble de la logique applicative côté utilisateur : interface graphique, capture d'écran via DXGI, encodage VP9, injection clavier/souris, et communication réseau.

- **Le serveur Go** : un serveur HTTP/WebSocket construit avec le framework `chi`, qui assure le rôle de relais de transport. Il expose une API REST complète pour la gestion des utilisateurs, des communautés et des sessions, et un canal WebSocket pour le routage en temps réel des messages et des trames vidéo binaires entre les clients.

### 2.2 Fonctionnalités principales

| Domaine | Fonctionnalité |
|---------|---------------|
| **Authentification** | Inscription, vérification e-mail, connexion, 2FA TOTP, codes de secours, réinitialisation de mot de passe, gestion de sessions multi-appareils |
| **Profil utilisateur** | Avatar, nom d'affichage, biographie, statut personnalisé (emoji + disponibilité), préférences de langue, fuseau horaire, thème |
| **Social** | Demandes d'amis, blocage, présence en ligne/hors-ligne en temps réel, messagerie directe 1:1 |

| **Communautés** | Création, rejoindre par code, hiérarchie Communauté → Département, rôles granulaires, annonces, messages, réactions, pièces jointes, invitations, approbation d'adhésion, bannissements, journal d'audit |
| **Contrôle à distance** | Invitation, appairage Contrôleur ↔ Agent, flux VP9 30–60 fps (capture DXGI), injection clavier, injection souris, streaming audio, transfert de fichiers, accès non accompagné, permissions granulaires, historique |
| **Administration** | Liste des utilisateurs, bannissement/débannissement, gestion des communautés, sessions actives, statistiques, journal d'audit global |
| **Conformité** | Export RGPD des données, suppression de compte programmée, historique des connexions avec géolocalisation IP |

### 2.3 Utilisateurs cibles

| Profil | Description |
|--------|-------------|
| **Agent de support technique** | Utilise le contrôle à distance pour assister les utilisateurs finaux à distance |
| **Utilisateur final (client)** | Accepte les sessions d'assistance et partage son écran |
| **Responsable d'équipe** | Crée et gère des communautés, attribue des rôles, consulte les journaux d'audit |
| **Administrateur plateforme** | Gère tous les utilisateurs, surveille les sessions actives, applique les politiques |

---

## 3. Architecture du système

### 3.1 Type d'architecture

BimStreaming adopte une architecture **client-serveur à deux niveaux** avec séparation stricte des responsabilités :

- Le **client** détient l'intégralité de la logique applicative (capture, encodage, rendu, gestion d'état).
- Le **serveur** est un **relais pur** : il ne traite pas les payloads des sessions de contrôle à distance, il les achemine entre les clients appairés.

Cette décision architecturale présente plusieurs avantages :
- Réduction de la charge CPU serveur (pas de transcoding vidéo).
- Confidentialité accrue (les données de session ne sont jamais persistées ni déchiffrées côté serveur).
- Scalabilité horizontale facilitée du serveur de relay.

### 3.2 Description des composants

#### Frontend (Client Flutter)

L'application cliente est développée avec **Flutter 3.11+** ciblant la plateforme **Windows Desktop**. Elle intègre :

- Un moteur d'interface graphique Material 3 avec support des thèmes clair/sombre.
- Un système de navigation déclaratif via `GoRouter`.
- Un gestionnaire d'état réactif via `Riverpod`.
- Un client HTTP pour les appels REST.
- Un client WebSocket pour les communications temps réel.
- Une couche de capture d'écran native via l'API **DXGI** (DirectX Graphics Infrastructure) exposée via FFI Win32.
- Un codec **VP9** natif (`bimstreaming_codec.dll`) pour l'encodage et le décodage des trames vidéo.
- Un moteur d'injection clavier/souris via l'API Win32.

#### Backend (Serveur Go)

Le serveur est développé en **Go 1.21+** avec le routeur `chi`. Il expose :

- Une **API REST** sous `/api/v1` pour toutes les opérations CRUD.
- Un **endpoint WebSocket** à `/api/v1/ws` pour le routage en temps réel.
- Un **hub WebSocket** pour la diffusion des événements de présence aux amis connectés.

L'architecture interne suit le **Repository Pattern** : les handlers HTTP appellent exclusivement les méthodes du repository, sans requêtes SQL directes dans les handlers.

#### Base de données

**PostgreSQL 16+** est utilisé comme seul système de persistance. La base de données est initialisée et migrée via `golang-migrate` avec 8 fichiers de migration numérotés séquentiellement, couvrant plus de 25 tables.

#### Relais WebSocket

Le composant de relais WebSocket gère deux types de messages :

1. **Messages JSON** (texte) : signaling de session (connection_request, connection_accept, session_message, register).
2. **Trames binaires VP9** : un en-tête binaire spécifique (`0xB1 0x4D`) précède chaque trame et encode l'identifiant du client cible.

### 3.3 Flux de données entre les composants

```
Client A (Contrôleur)                    Client B (Agent)
       │                                        │
       │─── POST /remote/sessions ─────────────►│ (via serveur REST)
       │◄── session_token ──────────────────────│
       │                                        │
       │─── WS: connection_request ────────────►│ (via hub WS)
       │◄── WS: connection_accept ──────────────│
       │                                        │
       │◄── Binary VP9 Frame (DXGI) ────────────│ (relais transparent)
       │                                        │
       │─── WS: session_message (input) ───────►│
       │    (keyboard/mouse events)             │
```

### 3.4 Diagramme d'architecture

```mermaid
graph TB
    subgraph CLIENT["Client Flutter (Windows Desktop)"]
        UI["Interface Utilisateur<br/>(Material 3 / GoRouter)"]
        STATE["Gestion d'état<br/>(Riverpod Providers)"]
        API_CLIENT["API Client<br/>(HTTP REST)"]
        WS_CLIENT["WS Client<br/>(WebSocket)"]
        SIGNAL["Signaling Service<br/>(Session Management)"]
        CAPTURE["DXGI Screen Capturer<br/>(Win32 FFI)"]
        CODEC["VP9 Codec<br/>(bimstreaming_codec.dll)"]
        INPUT["Keyboard/Mouse<br/>Injection Engine"]
    end

    subgraph SERVER["Serveur Go (:8080)"]
        CHI["chi Router<br/>(REST API /api/v1)"]
        WS_ROUTER["WS Router<br/>(Relay Engine)"]
        HUB["WS Hub<br/>(Presence & Events)"]
        HANDLERS["Handlers Layer<br/>(auth, communities, friends, remote...)"]
        REPO["Repository Layer<br/>(pgx / PostgreSQL)"]
        AUTH_SVC["Auth Service<br/>(JWT, bcrypt, TOTP, AES-256)"]
        MIDDLEWARE["Middleware<br/>(auth, audit, rate-limit, plan)"]
        EMAIL_SVC["Email Service<br/>(SMTP)"]
        GEOIP["GeoIP Client"]
    end

    subgraph DB["PostgreSQL 16+"]
        TABLES["25+ Tables<br/>(users, sessions, communities,<br/>messages, notifications...)"]
    end

    UI --> STATE
    STATE --> API_CLIENT
    STATE --> WS_CLIENT
    WS_CLIENT --> SIGNAL
    SIGNAL --> CAPTURE
    CAPTURE --> CODEC
    CODEC --> WS_CLIENT
    SIGNAL --> INPUT

    API_CLIENT -- "HTTP REST" --> CHI
    WS_CLIENT -- "WebSocket" --> WS_ROUTER

    CHI --> MIDDLEWARE
    MIDDLEWARE --> HANDLERS
    HANDLERS --> AUTH_SVC
    HANDLERS --> REPO
    HANDLERS --> EMAIL_SVC
    HANDLERS --> GEOIP
    HANDLERS --> HUB

    WS_ROUTER --> HUB
    WS_ROUTER -- "Binary VP9 relay" --> WS_CLIENT

    REPO -- "pgx driver" --> TABLES
```

---

## 4. Frontend — Application cliente Flutter

### 4.1 Technologies utilisées

| Technologie | Version | Rôle |
|-------------|---------|------|
| **Flutter** | 3.11+ | Framework UI cross-platform (target: Windows) |
| **Dart** | 3.x | Langage de programmation |
| **flutter_riverpod** | ^2.6.1 | Gestion d'état réactive |
| **go_router** | ^16.1.0 | Navigation déclarative |
| **web_socket_channel** | latest | WebSocket client |
| **http** | latest | Client HTTP REST |
| **flutter_secure_storage** | latest | Stockage sécurisé des credentials (JWT) |
| **shared_preferences** | latest | Préférences locales persistantes |
| **win32** | latest | Interopérabilité Win32 (DXGI, hooks clavier) |
| **file_picker** | latest | Sélection de fichiers |
| **window_manager** | latest | Contrôle de la fenêtre native Windows |
| **crypto** | latest | Opérations cryptographiques côté client |

### 4.2 Structure du projet

```
client/lib/
├── main.dart                          # Point d'entrée : ProviderScope + BimStreamingApp
├── app/
│   ├── router.dart                    # Définition des routes GoRouter
│   ├── pages/
│   │   ├── auth/                      # 7 écrans d'authentification
│   │   │   ├── login_page.dart
│   │   │   ├── register_page.dart
│   │   │   ├── two_factor_page.dart
│   │   │   ├── forgot_password_page.dart
│   │   │   ├── reset_code_page.dart
│   │   │   └── new_password_page.dart
│   │   └── profile_screen.dart
│   ├── state/
│   │   ├── auth_controller.dart       # Flux login/register/2FA
│   │   ├── data_providers.dart        # Providers Riverpod (users, communities, messages)
│   │   └── realtime_controller.dart   # Cycle de vie WebSocket
│   └── widgets/
│       └── app_shell.dart             # Shell de navigation principal
├── screens/
│   ├── friends_screen.dart
│   ├── communities_screen.dart
│   ├── notifications_screen.dart
│   └── remote_support_page.dart
├── services/
│   ├── api_client.dart                # Tous les appels REST
│   ├── ws_client.dart                 # Connexion WebSocket
│   ├── signaling_client_service.dart  # Signaling de session de contrôle
│   ├── file_transfer_service.dart
│   ├── remote_audio_service.dart
│   └── app_config.dart                # Configuration via --dart-define
├── native/
│   ├── dxgi_capturer.dart             # Capture d'écran DXGI (Win32 FFI)
│   └── vp9_codec.dart                 # Encodage/décodage VP9
└── services/keyboard/
    ├── keyboard_host_injection_engine.dart
    ├── keyboard_input_abstraction.dart
    └── keyboard_protocol.dart
```

### 4.3 Pages et composants principaux

| Route | Composant | Description |
|-------|-----------|-------------|
| `/auth/login` | `LoginPage` | Formulaire de connexion avec gestion des erreurs |
| `/auth/register` | `RegisterPage` | Inscription multi-étapes avec vérification e-mail |
| `/auth/2fa` | `TwoFactorPage` | Saisie du code TOTP ou code de secours |
| `/auth/forgot` | `ForgotPasswordPage` | Demande de réinitialisation par e-mail |
| `/auth/reset-code` | `ResetCodePage` | Vérification du code à 6 chiffres |
| `/auth/new-password` | `NewPasswordPage` | Définition du nouveau mot de passe |
| `/app/home` | `AppShell` | Shell principal avec navigation latérale |
| `/app/friends` | `FriendsScreen` | Liste d'amis, demandes, blocages |
| `/app/messages/:userId` | — | Conversation directe temps réel |
| `/app/communities/:communityId` | `CommunitiesScreen` | Canal communautaire |
| `/app/notifications` | `NotificationsScreen` | Centre de notifications |
| `/app/profile/:userId` | `ProfileScreen` | Profil public ou propre profil |
| `/app/settings` | — | Paramètres de l'application |

### 4.4 Gestion d'état

L'application utilise **Riverpod** comme solution de gestion d'état. Ce choix offre une inversion des dépendances stricte entre l'interface et la logique métier.

**Providers principaux :**

```dart
// Exemple de provider Riverpod (simplifié)
final authControllerProvider = StateNotifierProvider<AuthController, AuthState>(
  (ref) => AuthController(ref.watch(apiClientProvider)),
);

final realtimeControllerProvider = StateNotifierProvider<RealtimeController, RealtimeState>(
  (ref) => RealtimeController(ref.watch(wsClientProvider)),
);

final dataProvidersProvider = Provider<DataProviders>(
  (ref) => DataProviders(ref.watch(apiClientProvider)),
);
```

**Flux de données :**
1. L'UI observe les providers via `ref.watch()`.
2. Les interactions utilisateur appellent les méthodes des `StateNotifier`.
3. Les `StateNotifier` appellent les services (API client, WS client).
4. Les réponses mettent à jour l'état, déclenchant une reconstruction de l'UI.

### 4.5 Logique UI/UX

- **Thème** : Material Design 3 avec support dynamique des thèmes clair, sombre et système.
- **Internationalisation** : support multilingue via les préférences utilisateur (champ `language` en base).
- **Fenêtre native** : `window_manager` contrôle les dimensions et le comportement de la fenêtre Windows.
- **Notifications** : système de notifications in-app intégré avec badge de compteur non lu.
- **Présence** : indicateur de statut en ligne/hors-ligne mis à jour en temps réel via WebSocket.

### 4.6 Communication avec le backend

**REST HTTP :**

```dart
// client/lib/services/api_client.dart
class ApiClient {
  final String baseUrl;
  String? _accessToken;

  Future<Response> get(String path) async {
    return http.get(
      Uri.parse('$baseUrl$path'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );
  }
  // ...
}
```

**WebSocket :**

La connexion WebSocket est établie à l'authentification avec le token JWT en paramètre de requête :

```
ws://server:8080/api/v1/ws?token=<access_token>
```

Les messages sont des enveloppes JSON :

```json
{
  "type": "session_message",
  "session_id": "uuid",
  "from": "user-uuid",
  "to": "user-uuid",
  "data": { "toUserId": "..." }
}
```

---

## 5. Backend — Serveur Go

### 5.1 Technologies utilisées

| Technologie | Version | Rôle |
|-------------|---------|------|
| **Go** | 1.21+ | Langage de programmation |
| **chi** | v5 | Routeur HTTP léger et composable |
| **gorilla/websocket** | latest | Serveur WebSocket |
| **pgx** | v5 | Driver PostgreSQL natif haute performance |
| **golang-migrate** | v4 | Migrations de base de données |
| **google/uuid** | latest | Génération d'UUIDs v4 |
| **golang-jwt/jwt** | v5 | Émission et validation de JWT |
| **pquerna/otp** | latest | Génération et vérification TOTP (RFC 6238) |
| **bcrypt** | stdlib | Hachage des mots de passe |
| **crypto/aes** | stdlib | Chiffrement AES-256-GCM |

### 5.2 Architecture logicielle

Le serveur applique le **Repository Pattern** avec une séparation en trois couches :

```
HTTP Request
     │
     ▼
┌──────────────┐
│  Middleware   │  auth, audit, rate-limit, plan enforcement
└──────┬───────┘
       │
       ▼
┌──────────────┐
│   Handler    │  Validation, orchestration, réponse HTTP
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  Repository  │  Accès base de données (SQL via pgx)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  PostgreSQL  │
└──────────────┘
```

**Règle stricte** : aucune requête SQL n'est présente dans les handlers. Toute la logique d'accès aux données passe par le repository.

### 5.3 Conception des API REST

L'API respecte les conventions REST standard :

- Base path : `/api/v1`
- Format : JSON exclusivement
- Authentification : Bearer token JWT dans le header `Authorization`
- Erreurs : `{"error": "message descriptif"}`
- Codes HTTP : 200 OK, 201 Created, 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found, 409 Conflict, 500 Internal Server Error

**Exemple de handler (simplifié) :**

```go
// server/internal/handlers/auth_handler.go
func (a *App) Login(w http.ResponseWriter, r *http.Request) {
    var req LoginRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, `{"error":"invalid request"}`, http.StatusBadRequest)
        return
    }

    user, err := a.Repo.FindUserByEmail(r.Context(), req.Email)
    if err != nil || !bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)) {
        http.Error(w, `{"error":"invalid credentials"}`, http.StatusUnauthorized)
        return
    }

    accessToken, refreshToken, _ := a.Tokens.Issue(user.ID.String())
    json.NewEncoder(w).Encode(map[string]string{
        "access_token":  accessToken,
        "refresh_token": refreshToken,
    })
}
```

**Spécification complète** : le fichier `server/openapi.yaml` (38 KB) constitue la référence authoritative pour tous les contrats d'API.

### 5.4 Modules et services principaux

| Module | Fichier(s) | Responsabilité |
|--------|-----------|----------------|
| **Handlers** | `internal/handlers/*.go` | Validation des requêtes, orchestration, réponses HTTP |
| **Repository** | `internal/repository/` | Accès aux données PostgreSQL (un fichier par domaine) |
| **Auth** | `internal/auth/` | JWT (issue/parse/refresh), bcrypt, TOTP, AES-256-GCM |
| **WebSocket Hub** | `internal/ws/` | Registre des connexions WS actives, diffusion d'événements |
| **WebSocket Router** | `router.go` | Upgrade WS, relay JSON/binaire, gestion des sessions |
| **Email** | `internal/email/` | Envoi d'e-mails SMTP (vérification, réinitialisation) |
| **GeoIP** | `internal/geoip/` | Géolocalisation des adresses IP pour l'historique de connexion |
| **Storage** | `internal/storage/` | Service de fichiers pour avatars et pièces jointes |
| **Push** | `internal/push/` | Dispatcher de notifications push (FCM/APNs/Web) |
| **Middleware** | `internal/middleware/` | Authentification JWT, audit, rate limiting, plan enforcement |

### 5.5 Authentification et autorisation

**Flux d'authentification complet :**

1. **Inscription** : `POST /auth/register` → hachage bcrypt du mot de passe → envoi d'un e-mail de vérification.
2. **Vérification e-mail** : `POST /auth/verify-email` avec le token reçu par e-mail.
3. **Connexion** : `POST /auth/login` → vérification bcrypt → émission d'un access token (JWT, durée courte) et d'un refresh token (JWT, durée longue, stocké haché en base).
4. **2FA** : si activé, le login retourne un état intermédiaire `requires_2fa` → `POST /auth/2fa/challenge` avec le code TOTP.
5. **Renouvellement** : `POST /auth/refresh` avec le refresh token → nouvel access token.
6. **Révocation** : `POST /auth/logout` invalide le refresh token en base.

**Structure du JWT :**

```json
{
  "sub": "<user_uuid>",
  "exp": <timestamp>,
  "iat": <timestamp>
}
```

**Middleware d'authentification :**

```go
// server/internal/middleware/auth.go (simplifié)
func AuthMiddleware(tokenManager *auth.TokenManager) func(http.Handler) http.Handler {
    return func(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
            token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
            claims, err := tokenManager.ParseAccessToken(token)
            if err != nil {
                http.Error(w, `{"error":"unauthorized"}`, http.StatusUnauthorized)
                return
            }
            ctx := context.WithValue(r.Context(), "user_id", claims.Subject)
            next.ServeHTTP(w, r.WithContext(ctx))
        })
    }
}
```

**Application des plans d'abonnement :**

Le middleware `PlanEnforcer` intercepte les routes critiques et vérifie les quotas du plan de l'utilisateur avant d'autoriser l'opération :

```go
planMW.RequireMaxConcurrentSessions()    // Limite le nombre de sessions simultanées
planMW.RequireMaxCommunities()           // Limite la création de communautés
planMW.RequireFeature("unattended_access") // Vérifie l'accès à une fonctionnalité premium
```

### 5.6 Logique métier

**Relais WebSocket (router.go) :**

Le composant central du contrôle à distance est le `Router` WebSocket. Il maintient deux registres en mémoire :

- `ClientRegistry` : mapping `clientID → *Client` (connexion WebSocket active).
- `SessionRegistry` : mapping `sessionID → *Session` (paires contrôleur/agent).

**Traitement des trames VP9 binaires :**

```go
// Format de l'enveloppe binaire (router.go)
// [0]    0xB1  – magic byte 0
// [1]    0x4D  – magic byte 1
// [2-3]  version (ignorée)
// [4-7]  uint32LE: longueur du clientID cible (N)
// [8..8+N-1]  clientID cible (UTF-8)
// [reste]     payload VP9 opaque

func (r *Router) handleBinaryVideoFrame(msg []byte) {
    toIDLen := binary.LittleEndian.Uint32(msg[4:8])
    toClientID := string(msg[8 : 8+toIDLen])
    r.forwardTo(toClientID, msg) // Relay pur, sans décodage du payload
}
```

---

## 6. Conception de la base de données

### 6.1 Système de gestion choisi

**PostgreSQL 16+** a été retenu pour les raisons suivantes :
- Support natif des **UUID** via l'extension `pgcrypto`.
- Support de **JSONB** pour les champs flexibles (payload de notification, métadonnées).
- Intégrité référentielle forte via les **clés étrangères**.
- Support des **triggers** pour la mise à jour automatique du champ `updated_at`.
- Performance éprouvée pour les charges de type OLTP.

L'initialisation et l'évolution du schéma sont gérées par **golang-migrate**, avec 8 fichiers de migration numérotés séquentiellement.

### 6.2 Description des tables

#### Domaine Utilisateurs & Authentification

| Table | Description |
|-------|-------------|
| `users` | Table centrale. Contient le profil complet de l'utilisateur, les préférences, les indicateurs de sécurité (`locked_until`, `failed_login_count`, `is_banned`) |
| `email_verifications` | Tokens de vérification d'adresse e-mail avec expiration |
| `password_resets` | Codes de réinitialisation de mot de passe (stockés hachés) |
| `refresh_tokens` | Tokens de renouvellement JWT (stockés hachés, avec fingerprint d'appareil) |
| `device_sessions` | Sessions d'appareils identifiés par `device_id` |
| `totp_backup_codes` | Codes de secours 2FA (hachés, usage unique) |
| `trusted_devices` | Appareils de confiance exemptés de 2FA |
| `login_history` | Historique des connexions avec IP, pays, ville, OS, statut |
| `user_status` | Statut personnalisé (emoji, message, disponibilité, expiration) |
| `audit_logs` | Journal d'audit global des actions utilisateur |

#### Domaine Communautés

| Table | Description |
|-------|-------------|
| `communities` | Communautés avec code unique, description, visibilité publique/privée |
| `departments` | Sous-groupes d'une communauté (hiérarchie) |
| `community_members` | Table de liaison utilisateur-communauté avec rôle et statut |
| `join_requests` | Demandes d'adhésion en attente d'approbation |
| `community_announcements` | Annonces épinglées dans une communauté |
| `community_invites` | Liens d'invitation avec quota d'utilisations et expiration |
| `community_bans` | Bannissements de membres avec motif et expiration optionnelle |
| `community_audit_log` | Journal d'audit des actions au niveau communauté |

#### Domaine Social & Messagerie

| Table | Description |
|-------|-------------|
| `friendships` | Relations d'amitié bidirectionnelles (pending/accepted/blocked) |
| `direct_messages` | Messages directs 1:1 avec support reply, édition et suppression logique |
| `community_messages` | Messages dans les canaux communautaires |
| `message_reactions` | Réactions emoji sur les messages (DM ou communauté) |
| `message_attachments` | Pièces jointes avec métadonnées (nom, taille, MIME, URL) |
| `notifications` | Notifications utilisateur avec payload JSONB |

#### Domaine Contrôle à Distance

| Table | Description |
|-------|-------------|
| `remote_session_invites` | Invitations de session avec token et expiration |
| `remote_sessions` | Sessions actives/terminées avec métriques (latence, bytes, durée) |
| `session_permissions` | Permissions granulaires par session (clavier, souris, presse-papiers, fichiers, audio) |
| `unattended_access` | Tokens d'accès non accompagné entre paires hôte/contrôleur |
| `activity_log` | Historique des activités de session (type, durée, statut) |

#### Domaine Abonnements & RGPD

| Table | Description |
|-------|-------------|
| `plans` | Définition des plans (Free/Pro/Team/Enterprise) avec quotas et prix |
| `user_subscriptions` | Abonnement actif d'un utilisateur avec cycle de facturation et statut |
| `push_tokens` | Tokens de notification push par plateforme (FCM/APNs/Web) |
| `data_export_requests` | Requêtes d'export RGPD avec statut et URL de téléchargement |
| `account_deletion_requests` | Requêtes de suppression de compte programmées |

### 6.3 Relations entre entités

Les principales relations sont :

- `users` ←1:N→ `refresh_tokens`, `device_sessions`, `notifications`, `login_history`
- `users` ←N:M→ `users` via `friendships`
- `users` ←N:M→ `communities` via `community_members`
- `communities` ←1:N→ `departments`, `community_messages`, `community_announcements`
- `remote_sessions` ←1:1→ `session_permissions`
- `users` ←1:1→ `user_status`, `user_subscriptions`

### 6.4 Contraintes et indexation

**Contraintes métier notables :**

```sql
-- Auto-incrémentation updated_at via trigger
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Unicité bidirectionnelle des amitiés
CREATE UNIQUE INDEX idx_friendships_pair_unique
  ON friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));

-- Interdiction d'auto-amitié
CONSTRAINT chk_friendship_not_self CHECK (requester_id <> addressee_id)

-- Unicité combinée communauté/membre
UNIQUE (community_id, user_id)  -- dans community_members

-- Rôles valides
CHECK (role IN ('owner', 'admin', 'admin_sec', 'tech', 'user', 'viewer'))

-- Plans d'abonnement
INSERT INTO plans (name, ...) VALUES
  ('free', ...), ('pro', ...), ('team', ...), ('enterprise', ...)
```

**Indexes stratégiques :**

```sql
-- Recherche rapide par email/username
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_username ON users(username);

-- Messages triés chronologiquement
CREATE INDEX idx_direct_messages_pair_created_at
  ON direct_messages(sender_id, recipient_id, created_at DESC);

-- Notifications non lues par utilisateur
CREATE INDEX idx_notifications_user_read_created
  ON notifications(user_id, is_read, created_at DESC);

-- Sessions de contrôle
CREATE INDEX idx_remote_sessions_host_controller
  ON remote_sessions(host_id, controller_id);
CREATE INDEX idx_remote_sessions_token ON remote_sessions(session_token);
```

### 6.5 Diagramme Entité-Relation

```mermaid
erDiagram
    USERS {
        uuid id PK
        text username UK
        text email UK
        text password_hash
        text avatar_url
        text display_name
        boolean is_verified
        boolean is_online
        boolean two_factor_enabled
        text theme
        text language
        text timezone
        boolean is_banned
        int failed_login_count
        timestamptz locked_until
        timestamptz created_at
    }

    USER_STATUS {
        uuid id PK
        uuid user_id FK
        text emoji
        text message
        text availability
        timestamptz expires_at
    }

    FRIENDSHIPS {
        uuid id PK
        uuid requester_id FK
        uuid addressee_id FK
        text status
    }

    DIRECT_MESSAGES {
        uuid id PK
        uuid sender_id FK
        uuid recipient_id FK
        text content
        boolean is_read
        boolean is_edited
        boolean is_deleted
    }

    COMMUNITIES {
        uuid id PK
        text code UK
        text name
        uuid owner_id FK
        boolean is_public
        text description
    }

    DEPARTMENTS {
        uuid id PK
        uuid community_id FK
        text name
    }

    COMMUNITY_MEMBERS {
        uuid id PK
        uuid community_id FK
        uuid user_id FK
        uuid department_id FK
        text role
        text status
    }

    COMMUNITY_MESSAGES {
        uuid id PK
        uuid community_id FK
        uuid sender_id FK
        text content
        boolean is_edited
        boolean is_deleted
    }

    NOTIFICATIONS {
        uuid id PK
        uuid user_id FK
        text type
        jsonb payload
        boolean is_read
    }

    REMOTE_SESSIONS {
        uuid id PK
        uuid controller_id FK
        uuid host_id FK
        text session_token UK
        text session_type
        text quality
        timestamptz started_at
        timestamptz ended_at
        int avg_latency_ms
        bigint bytes_sent
    }

    SESSION_PERMISSIONS {
        uuid id PK
        uuid session_id FK
        boolean allow_keyboard
        boolean allow_mouse
        boolean allow_clipboard
        boolean allow_file_transfer
        boolean allow_audio
    }

    UNATTENDED_ACCESS {
        uuid id PK
        uuid host_user_id FK
        uuid controller_user_id FK
        text access_password_hash
        boolean is_active
    }

    PLANS {
        uuid id PK
        text name UK
        int max_concurrent_sessions
        int max_community_members
        int max_communities
        boolean unattended_access
        numeric price_monthly_usd
    }

    USER_SUBSCRIPTIONS {
        uuid id PK
        uuid user_id FK
        uuid plan_id FK
        text status
        text billing_cycle
    }

    USERS ||--o{ FRIENDSHIPS : "requester_id / addressee_id"
    USERS ||--o{ DIRECT_MESSAGES : "sender_id / recipient_id"
    USERS ||--o{ COMMUNITY_MEMBERS : "user_id"
    USERS ||--o{ NOTIFICATIONS : "user_id"
    USERS ||--o| USER_STATUS : "user_id"
    USERS ||--o| USER_SUBSCRIPTIONS : "user_id"
    COMMUNITIES ||--o{ DEPARTMENTS : "community_id"
    COMMUNITIES ||--o{ COMMUNITY_MEMBERS : "community_id"
    COMMUNITIES ||--o{ COMMUNITY_MESSAGES : "community_id"
    DEPARTMENTS ||--o{ COMMUNITY_MEMBERS : "department_id"
    REMOTE_SESSIONS ||--|| SESSION_PERMISSIONS : "session_id"
    USERS ||--o{ REMOTE_SESSIONS : "controller_id / host_id"
    USERS ||--o{ UNATTENDED_ACCESS : "host / controller"
    USER_SUBSCRIPTIONS }o--|| PLANS : "plan_id"
```

---

## 7. Serveur et déploiement

### 7.1 Rôle du serveur

Le serveur BimStreaming remplit trois rôles distincts :

1. **API REST** : expose 60+ endpoints REST sous `/api/v1` pour toutes les opérations CRUD (utilisateurs, communautés, amis, messages, sessions).
2. **Relais WebSocket transparent** : achemine les messages JSON de signaling et les trames binaires VP9 entre les clients appairés, sans décodage du payload.
3. **Hub de présence** : diffuse les événements de présence (`user:online`, `user:offline`) aux amis connectés d'un utilisateur via le hub WebSocket interne.

### 7.2 Environnement et configuration

**Configuration via variables d'environnement (`server/.env`) :**

```env
# Base de données
DATABASE_URL=postgres://user:pass@host:5432/bimstreaming?sslmode=require

# Serveur
SERVER_ADDR=0.0.0.0:8080

# Sécurité
JWT_SECRET=<32-byte hex>
JWT_REFRESH_SECRET=<32-byte hex>
ENCRYPTION_KEY=<32-char string>

# SMTP
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=noreply@example.com
SMTP_PASS=<password>
SMTP_FROM=BimStreaming <noreply@example.com>

# Application
APP_BASE_URL=http://192.168.1.207:8080
AVATAR_STORAGE_PATH=./storage/avatars
MAX_UPLOAD_SIZE_MB=5
RATE_LIMIT_ENABLED=false
```

**Endpoints exposés :**

| Endpoint | Protocole | Description |
|----------|-----------|-------------|
| `/healthz` | HTTP GET | Health check (retourne `200 OK`) |
| `/api/v1/*` | HTTP REST | Toutes les routes API |
| `/api/v1/ws` | WebSocket | Canal temps réel |
| `/media/avatars/{filename}` | HTTP GET | Fichiers avatar (publics) |
| `/media/attachments/{filename}` | HTTP GET | Pièces jointes |

### 7.3 Processus de déploiement

**Compilation du binaire serveur :**

```powershell
cd server
go build -o build/bimstreaming-server.exe .
```

**Application des migrations :**

```powershell
migrate -path .\server\migrations -database "$env:DATABASE_URL" up
```

**Démarrage unifié (développement) :**

```powershell
# Depuis la racine du projet
.\start-dev.ps1 -SignalUrl ws://192.168.1.207:8080/api/v1/ws -Mode release
```

**Compilation du client Windows :**

```powershell
cd client
flutter build windows --release `
  --dart-define=BIM_SIGNAL_URL=ws://SERVER_IP:8080/api/v1/ws
```

### 7.4 Considérations de performance

- **Canaux Go** : la file d'envoi WebSocket de chaque client est un canal Go bufferisé (`chan []byte, 256`). En cas de débordement, les messages sont abandonnés avec journalisation, évitant les blocages de goroutines.
- **Relay sans copie** : les trames binaires VP9 sont forwardées sans désérialisation ni copie de payload.
- **Rate limiting** : configurable via `RATE_LIMIT_ENABLED` (applicable sur les routes d'authentification).
- **Indexes PostgreSQL** : 20+ indexes stratégiques couvrent les requêtes fréquentes (paires d'amis, messages triés par date, sessions actives).
- **Triggers `updated_at`** : chaque table dispose d'un trigger `BEFORE UPDATE` pour maintenir le champ `updated_at` sans logique applicative.

---

## 8. Cas d'utilisation et workflows principaux

### 8.1 Authentification et connexion

```mermaid
sequenceDiagram
    actor User
    participant Client as Flutter Client
    participant Server as Go Server
    participant DB as PostgreSQL
    participant Email as SMTP

    User->>Client: Saisit email + mot de passe
    Client->>Server: POST /auth/login
    Server->>DB: SELECT user WHERE email = ?
    DB-->>Server: user record
    Server->>Server: bcrypt.Compare(password, hash)

    alt 2FA désactivé
        Server-->>Client: {access_token, refresh_token}
        Client->>Client: Stocke tokens (flutter_secure_storage)
        Client-->>User: Redirection vers /app/home
    else 2FA activé
        Server-->>Client: {status: "requires_2fa"}
        Client-->>User: Affiche écran TOTP
        User->>Client: Saisit code TOTP à 6 chiffres
        Client->>Server: POST /auth/2fa/challenge {code}
        Server->>Server: TOTP.Validate(secret, code)
        Server-->>Client: {access_token, refresh_token}
        Client-->>User: Redirection vers /app/home
    end

    Client->>Server: GET /api/v1/ws?token=<access_token>
    Server->>Server: ParseAccessToken(token)
    Server-->>Client: WebSocket établi
    Server->>DB: UPDATE users SET is_online = true
    Server->>Server: Hub.Broadcast(friends, "user:online")
```

### 8.2 Établissement d'une session de contrôle à distance

```mermaid
sequenceDiagram
    actor Controller as Contrôleur
    actor Agent as Agent (machine distante)
    participant Server as Go Server (relay)
    participant DB as PostgreSQL

    Controller->>Server: POST /remote/invite/{agent_user_id}
    Server->>DB: INSERT remote_session_invites
    Server-->>Controller: {invite_id, expires_at}

    Server->>Agent: WS Event: "remote_invite_received"
    Agent->>Server: PATCH /remote/invite/{id} {action: "accept"}
    Server->>DB: UPDATE invite status = 'accepted'

    Controller->>Server: POST /remote/sessions
    Server->>DB: INSERT remote_sessions + session_permissions
    Server-->>Controller: {session_id, session_token}

    Controller->>Server: WS: {type: "connection_request", session_id, to: agent_id}
    Server->>Agent: WS relay: connection_request
    Agent-->>Server: WS: {type: "connection_accept", session_id, to: controller_id}
    Server-->>Controller: WS relay: connection_accept

    loop Streaming VP9 à 30-60 fps
        Agent->>Agent: DXGI CaptureScreen()
        Agent->>Agent: VP9.Encode(frame)
        Agent->>Server: WS Binary [0xB1 0x4D | target_id | VP9 payload]
        Server->>Controller: WS Binary relay (transparent)
        Controller->>Controller: VP9.Decode(frame)
        Controller->>Controller: RenderFrame()
    end

    loop Injection d'entrées
        Controller->>Server: WS: {type: "session_message", data: {keyboard/mouse event}}
        Server->>Agent: WS relay: session_message
        Agent->>Agent: Win32.InjectInput(event)
    end

    Controller->>Server: POST /remote/sessions/{id}/end
    Server->>DB: UPDATE remote_sessions SET ended_at, duration_seconds
```

### 8.3 Messagerie en temps réel

```mermaid
sequenceDiagram
    actor UserA as Utilisateur A
    actor UserB as Utilisateur B
    participant Client as Flutter Client
    participant Server as Go Server
    participant DB as PostgreSQL

    UserA->>Client: Saisit un message dans la conversation
    Client->>Server: POST /dm/{user_b_id} {content: "Bonjour"}
    Server->>DB: INSERT direct_messages
    Server-->>Client: {message_id, created_at}

    Server->>Server: Hub.PublishToUser(user_b_id, "dm:new", message)

    Note over Server: Si UserB est connecté via WebSocket
    Server->>UserB: WS Event: {type: "dm:new", message: {...}}
    UserB->>UserB: Riverpod provider invalidé
    UserB->>UserB: UI mise à jour (nouveau message affiché)

    UserB->>Server: PATCH /dm/{user_a_id}/read
    Server->>DB: UPDATE direct_messages SET is_read = true
    Server->>UserA: WS Event: {type: "dm:read", user_id: user_b_id}
```

---

## 9. Défis techniques et solutions

### 9.1 Streaming vidéo haute fréquence sur réseau local

**Problème :** Les solutions de contrôle à distance classiques limitent le débit à 10–15 fps sur les connexions WebSocket standard. L'objectif de BimStreaming est d'atteindre 30–60 fps avec une latence acceptable sur un réseau local d'entreprise.

**Solution adoptée :**

- **Capture DXGI** : utilisation de l'API DirectX Graphics Infrastructure (DXGI) pour la capture d'écran, nettement plus performante que GDI ou l'API de capture Windows (`BitBlt`). DXGI opère au niveau du compositeur de bureau et accède directement au framebuffer GPU.
- **Codec VP9** : encodage avec un codec vidéo moderne (VP9) optimisé pour la compression à débit variable. Un `bimstreaming_codec.dll` natif est lié au client Flutter via FFI.
- **Transport binaire direct** : les trames VP9 sont transmises comme messages WebSocket binaires avec un en-tête minimal, évitant le surcoût de l'encodage Base64.
- **Relay sans traitement** : le serveur transmet les trames sans désérialisation, réduisant la latence ajoutée à celle du réseau uniquement.

**Résultat :** 30 fps stable atteint en release, avec des pics à 60 fps sur réseau local Gigabit.

### 9.2 Architecture relay vs peer-to-peer

**Problème :** Une connexion peer-to-peer (WebRTC) offrirait une latence optimale mais introduit des complications : traversée NAT, gestion des ICE candidates, dépendance à des serveurs STUN/TURN.

**Décision architecturale :** Utilisation d'un relay WebSocket via le serveur applicatif.

**Avantages :**
- Déploiement simplifié (pas de serveur STUN/TURN séparé).
- Compatibilité réseau totale (pas de problème de traversée NAT).
- Confidentialité : même si le relay voit les octets, la logique de chiffrement peut être ajoutée en bout en bout.

**Compromis :**
- Latence légèrement supérieure (deux sauts réseau au lieu d'un).
- Bande passante serveur proportionnelle au nombre de sessions actives.

### 9.3 Gestion de la présence en temps réel

**Problème :** Informer tous les amis d'un utilisateur de son changement de présence (connexion/déconnexion) de manière efficace et sans polling.

**Solution :**

```go
// router.go — à la déconnexion WebSocket
func (r *Router) setPresenceAndBroadcast(userID string, online bool) {
    r.repo.SetOnlineStatus(ctx, parsed, online)
    friendIDs := r.repo.ListAcceptedFriendIDs(ctx, parsed)
    targets := append([]string{userID}, friendIDs...)
    r.hub.PublishToMany(targets, eventType, map[string]string{"user_id": userID})
}
```

Le hub WebSocket diffuse l'événement à tous les amis connectés en O(n) avec n = nombre d'amis en ligne.

### 9.4 Injection de clavier sur Windows

**Problème :** L'injection d'événements clavier via Win32 (`SendInput`) ne fonctionne pas correctement avec certaines applications qui interceptent les événements au niveau du noyau (jeux, applications de sécurité).

**Solution :** Implémentation d'un moteur d'injection à trois niveaux dans `keyboard_host_injection_engine.dart` :

1. `SendInput` — injection standard (compatibilité maximale).
2. `PostMessage` — injection via la file de messages de la fenêtre cible.
3. Hook clavier au niveau noyau via `SetWindowsHookEx` — pour les applications qui interceptent `WM_KEYDOWN`.

---

## 10. Sécurité

### 10.1 Protection des données

| Mécanisme | Implémentation |
|-----------|---------------|
| **Hachage des mots de passe** | `bcrypt` avec coût adaptatif (Go stdlib) |
| **Tokens de réinitialisation** | Stockés hachés (`token_hash`) en base, jamais en clair |
| **Chiffrement des payloads sensibles** | AES-256-GCM via `ENCRYPTION_KEY` (32 caractères) |
| **Stockage sécurisé client** | `flutter_secure_storage` (Windows Credential Manager) |
| **Tokens de backup 2FA** | Stockés hachés (`code_hash`), usage unique |
| **Refresh tokens** | Stockés hachés avec fingerprint d'appareil |
| **Taille max upload** | Configurable via `MAX_UPLOAD_SIZE_MB` (défaut : 5 MB) |

### 10.2 Mécanismes d'authentification

**JWT dual-token :**
- **Access token** : durée courte (typiquement 15 minutes), transmis dans chaque requête HTTP.
- **Refresh token** : durée longue (typiquement 30 jours), stocké haché en base, utilisé uniquement pour obtenir un nouvel access token.

**2FA TOTP (RFC 6238) :**
- Secret généré à l'activation, stocké chiffré en base.
- Code à 6 chiffres valide 30 secondes avec fenêtre de tolérance d'un intervalle.
- 10 codes de secours à usage unique générés à l'activation.

**Gestion des tentatives échouées :**
```sql
-- Migration 007 : champs de sécurité sur users
locked_until TIMESTAMPTZ,        -- Verrouillage temporaire
failed_login_count INTEGER,       -- Compteur de tentatives
last_failed_login_at TIMESTAMPTZ, -- Dernière tentative échouée
is_banned BOOLEAN                 -- Bannissement permanent
```

**Appareils de confiance :** après vérification 2FA réussie, l'appareil peut être marqué comme de confiance pour bypasser la 2FA lors des connexions suivantes.

### 10.3 Vulnérabilités traitées

| Vulnérabilité | Mesure |
|---------------|--------|
| **Brute force** | Verrouillage de compte après N tentatives échouées |
| **Réutilisation de tokens** | Révocation des refresh tokens en base à chaque logout |
| **CSRF** | Pas de cookies ; authentification par Bearer token uniquement |
| **Injection SQL** | Utilisation de `pgx` avec requêtes paramétrées exclusivement |
| **Enumération d'utilisateurs** | Messages d'erreur génériques sur login/register |
| **Upload malveillant** | Limitation de taille, vérification du MIME type |
| **Compte non vérifié** | Les utilisateurs non vérifiés par e-mail ne peuvent pas se connecter |
| **Rate limiting** | Middleware configurable sur les routes d'authentification |
| **Audit trail** | Toutes les actions sensibles sont loguées dans `audit_logs` |
| **Conformité RGPD** | Export de données et suppression de compte implémentés |

---

## 11. Optimisation des performances

### 11.1 Couche réseau

| Optimisation | Description |
|-------------|-------------|
| **File d'envoi WS bufferisée** | `chan []byte, 256` par client ; message abandonné si pleine (pas de blocage) |
| **Goroutines dédiées** | Une goroutine `readLoop` et une `writeLoop` par client WebSocket |
| **Relay binaire sans copie** | Trames VP9 transmises sans désérialisation ni recopie de payload |
| **Multiplexage Go** | Le scheduler Go gère des milliers de goroutines concurrentes légèrement |

### 11.2 Capture d'écran et encodage

| Optimisation | Description |
|-------------|-------------|
| **DXGI DDI** | Capture au niveau du compositeur de bureau, zéro copie GPU |
| **VP9 adaptatif** | Débit variable ajusté à la bande passante disponible |
| **Delta frames** | Encodage différentiel : seules les zones modifiées de l'écran sont envoyées |
| **Qualité configurable** | Endpoint `PATCH /remote/sessions/{id}/quality` : auto/low/medium/high/ultra |

### 11.3 Base de données

| Optimisation | Description |
|-------------|-------------|
| **Indexes composites** | 20+ indexes sur les requêtes fréquentes (paires DM, sessions, notifications) |
| **Triggers automatiques** | `set_updated_at()` sans surcharge applicative |
| **JSONB pour payloads** | Champs flexibles (notifications, métadonnées) sans colonnes dynamiques |
| **Soft delete** | `deleted_at` sur les tables sensibles (users, communities) pour audit |

---

## 12. Tests

### 12.1 Stratégie de test

La stratégie de test adoptée pour ce projet distingue plusieurs niveaux :

| Niveau | Périmètre | Outils |
|--------|-----------|--------|
| **Tests unitaires serveur** | Handlers, repository, auth | `go test`, `testify` |
| **Tests d'intégration** | API REST complète avec base de test | `net/http/httptest`, PostgreSQL de test |
| **Tests unitaires client** | Providers Riverpod, services | `flutter_test` |
| **Tests de widget** | Composants UI isolés | `flutter_test`, `golden_toolkit` |
| **Tests end-to-end** | Flux complets (login, session) | Manuel |

### 12.2 Exemples de cas de test serveur

```go
// Test d'authentification (simplifié)
func TestLogin_ValidCredentials(t *testing.T) {
    app := setupTestApp(t)
    body := `{"email":"test@example.com","password":"SecurePass123!"}`

    req := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(body))
    req.Header.Set("Content-Type", "application/json")
    w := httptest.NewRecorder()

    app.Login(w, req)

    assert.Equal(t, http.StatusOK, w.Code)
    var resp map[string]string
    json.NewDecoder(w.Body).Decode(&resp)
    assert.NotEmpty(t, resp["access_token"])
    assert.NotEmpty(t, resp["refresh_token"])
}

func TestLogin_WrongPassword_Returns401(t *testing.T) {
    app := setupTestApp(t)
    body := `{"email":"test@example.com","password":"WrongPassword"}`

    req := httptest.NewRequest(http.MethodPost, "/auth/login", strings.NewReader(body))
    w := httptest.NewRecorder()
    app.Login(w, req)

    assert.Equal(t, http.StatusUnauthorized, w.Code)
}
```

### 12.3 Exemples de cas de test client

```dart
// Test du provider d'authentification
testWidgets('Login success updates auth state', (tester) async {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(MockApiClient()),
    ],
  );

  final controller = container.read(authControllerProvider.notifier);
  await controller.login('user@test.com', 'password');

  expect(
    container.read(authControllerProvider),
    isA<AuthState>().having((s) => s.isAuthenticated, 'isAuthenticated', true),
  );
});
```

---

## 13. Améliorations futures

### 13.1 Évolutions fonctionnelles

| Amélioration | Description | Priorité |
|-------------|-------------|---------|
| **Connexion peer-to-peer** | Remplacement du relay par WebRTC pour réduire la latence et la bande passante serveur | Haute |
| **Applications mobiles** | Portage du client Flutter vers iOS et Android | Haute |
| **Application web** | Client Flutter Web pour accès sans installation | Moyenne |
| **Enregistrement de sessions** | Sauvegarde et relecture des sessions de contrôle à distance | Moyenne |
| **Tableau de bord d'administration** | Interface graphique dédiée à l'administration plateforme | Moyenne |
| **Intégration paiement** | Module de facturation pour les plans Pro/Team/Enterprise | Haute |
| **Chiffrement bout-en-bout** | Chiffrement E2E des sessions de contrôle (actuellement chiffré en transit) | Haute |

### 13.2 Optimisations techniques

| Optimisation | Description |
|-------------|-------------|
| **WebRTC pour le relay** | Éliminer le saut serveur pour le streaming vidéo |
| **Compression différentielle avancée** | Encoder uniquement les régions modifiées de l'écran (tiles) |
| **Scalabilité horizontale** | Remplacer le registre de clients en mémoire par Redis pour supporter plusieurs instances serveur |
| **CDN pour les médias** | Déporter le service de fichiers vers un stockage objet (S3/MinIO) |
| **Monitoring** | Intégration Prometheus/Grafana pour les métriques de session et de présence |
| **Tests automatisés** | Couverture de test complète avec CI/CD (GitHub Actions) |
| **Migration vers gRPC** | Pour les messages de session à haute fréquence (alternative au WebSocket JSON) |

### 13.3 Sécurité

| Amélioration | Description |
|-------------|-------------|
| **Chiffrement E2E des sessions** | Clés de session négociées entre contrôleur et agent, invisibles au serveur |
| **Certificats de dispositif** | Authentification des appareils par certificat plutôt que par `device_id` |
| **Audit avancé** | Intégration d'un SIEM externe pour l'analyse des journaux |
| **Conformité SOC 2** | Implémentation des contrôles requis pour la certification SOC 2 |

---

## 14. Conclusion

### 14.1 Résumé du travail réalisé

Ce projet a abouti à la conception et au développement complet d'une plateforme de support à distance et de collaboration d'équipe pour Windows. Les réalisations techniques principales sont :

1. **Architecture client-serveur strict** avec séparation des responsabilités : le client détient la logique applicative, le serveur assure le transport et la persistance.

2. **Backend Go robuste** avec 60+ endpoints REST, authentification JWT complète (2FA TOTP, backup codes, appareils de confiance), et relais WebSocket transparent pour les sessions de contrôle.

3. **Base de données relationnelle complète** : 25+ tables PostgreSQL couvrant l'ensemble des domaines fonctionnels, avec 8 migrations évolutives, une indexation stratégique, et des triggers automatiques.

4. **Streaming vidéo performant** : capture DXGI, encodage VP9 natif, transmission binaire directe sur WebSocket, atteignant 30–60 fps sur réseau local.

5. **Sécurité en profondeur** : bcrypt, JWT dual-token, TOTP, AES-256-GCM, audit logging, verrouillage de compte, conformité RGPD.

6. **Fonctionnalités communautaires complètes** : hiérarchie Communauté → Département, rôles granulaires, messagerie temps réel, réactions, pièces jointes, gestion des membres.

### 14.2 Résultats obtenus

| Objectif | Résultat |
|---------|---------|
| Contrôle à distance 30–60 fps | ✅ Atteint (30 fps stable, 60 fps réseau local) |
| API REST complète | ✅ 60+ endpoints documentés (OpenAPI 3.0) |
| Authentification sécurisée | ✅ Email, 2FA TOTP, JWT, verrouillage de compte |
| Messagerie temps réel | ✅ DM 1:1 et canaux communautaires via WebSocket |
| Conformité RGPD | ✅ Export données et suppression de compte |
| Plans d'abonnement | ✅ Free/Pro/Team/Enterprise avec enforcement middleware |
| Windows desktop | ✅ Flutter build natif, Win32 FFI pour DXGI et injection |

### 14.3 Compétences acquises

Ce projet a permis d'approfondir les compétences suivantes :

- Développement backend en Go avec architecture en couches (handlers, repository, middleware).
- Conception et modélisation de bases de données relationnelles complexes.
- Développement d'applications desktop performantes avec Flutter et interopérabilité Win32.
- Implémentation de protocoles de sécurité modernes (JWT, TOTP, bcrypt, AES-256).
- Conception de systèmes temps réel avec WebSocket et broadcasting de présence.
- Optimisation du streaming vidéo pour des applications de contrôle à distance.

---

*Document généré pour le Projet de Fin d'Études (PFE) — BimStreaming v1.2.0 — Mai 2026*
