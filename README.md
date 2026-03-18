# BimStreaming – Projet PFE

Application desktop Flutter (Windows) pour le support à distance, avec gestion multi-rôles, navigation sécurisée, interface bilingue (français/anglais) et espace de session support.

## 1) Contexte et objectif du PFE

Ce projet vise à proposer une base de plateforme de support à distance interne, organisée par pays et départements, avec:

- un contrôle d’accès par rôles,
- une visualisation des utilisateurs/appareils,
- un espace de session support (chat, transfert, commandes),
- une expérience fluide en desktop Windows.

## 2) Périmètre fonctionnel

### Fonctionnalités implémentées

- Interface desktop Flutter pour Windows.
- Sidebar masquée par défaut (ouverte via bouton hamburger).
- Gestion des pages: Remote Control, Devices, History, Authentication, Settings, Support.
- Gestion hiérarchique des utilisateurs:
  - Pays
  - Départements
  - Admins et utilisateurs
- Filtres et recherche dans Devices.
- Session support:
  - zone vidéo centrale,
  - panneau latéral (chat/transfert/commande),
  - bouton d’agrandissement,
  - mode plein écran de la fenêtre Windows.
- Persistance des préférences (langue, thème) via `shared_preferences`.

### Règle de connexion par rôle

- Rôle `User` (y compris mode non authentifié):
  - clic sur un autre utilisateur/appareil ⇒ popup “en attente d’acceptation”.
- Autres rôles (`Admin Principal`, `Admin Pays`, `Admin Département`, `Technicien Informatique`):
  - clic ⇒ ouverture directe de la page Support streaming.

## 3) Architecture technique (version actuelle)

- Framework: Flutter / Dart
- Plateforme cible principale: Windows
- Fichier principal: [lib/main.dart](lib/main.dart)

### Dépendances clés

- `flutter_localizations`
- `shared_preferences`
- `file_picker`
- `window_manager`

Configuration complète: [pubspec.yaml](pubspec.yaml)

## 4) Comptes de test

Identifiants utilisés pour la démonstration:

- Admin Principal: `PADM001` / `32d18f26`
- Admin Pays: `CADM001` / `countryadmin`
- Admin Département: `ADM001` / `admin123`
- User: `USR001` / `pass123`
- Technicien Informatique: `USR003` / `pass123`
- Code de récupération: `123456`

Source: [authentifiacation.md](authentifiacation.md)

## 5) Installation et exécution

### Prérequis

- Flutter SDK installé.
- Windows desktop activé:

```bash
flutter config --enable-windows-desktop
```

- Visual Studio Build Tools (Desktop development with C++).

### Commandes

```bash
flutter pub get
flutter run -d windows
```

### Exécution sur 2 machines physiques (même réseau)

Par défaut, le client utilise `ws://127.0.0.1:8080/api/v1/ws` (localhost), ce qui ne fonctionne que sur une seule machine.
Pour connecter deux PC physiques, configurez l'URL WebSocket du serveur avec son IP LAN.

PowerShell (sur chaque PC client):

```powershell
$env:BIM_SIGNAL_URL = 'ws://192.168.1.50:8080/api/v1/ws'
flutter run -d windows
```

Alternative avec dart-define:

```powershell
flutter run -d windows --dart-define=BIM_SIGNAL_URL=ws://192.168.1.50:8080/api/v1/ws
```

## 6) Scénarios de démonstration (soutenance)

### Scénario A – Utilisateur standard (sans authentification)

1. Ouvrir l’application.
2. Aller dans Devices.
3. Cliquer sur un utilisateur/appareil.
4. Résultat attendu: popup d’attente d’acceptation.

### Scénario B – Technicien/Admin

1. S’authentifier avec un rôle technique/admin.
2. Aller dans Devices.
3. Cliquer sur un utilisateur.
4. Résultat attendu: ouverture directe de la page Support streaming.

### Scénario C – Support plein écran

1. Depuis Support, cliquer sur le bouton agrandir de la zone vidéo.
2. Résultat attendu: agrandissement de la zone + mode plein écran de la fenêtre Windows.

## 7) Structure du projet (essentiel)

- [lib/main.dart](lib/main.dart): logique applicative, UI, rôles, navigation, support.
- [windows](windows): configuration desktop Windows.
- [authentifiacation.md](authentifiacation.md): identifiants de démonstration.

## 8) Captures recommandées pour le rapport

Pour documenter le PFE, ajouter des captures de:

- écran d’accueil + sidebar cachée,
- page Devices (structure pays/départements/utilisateurs),
- popup d’attente côté User,
- page Support ouverte par Admin/Technicien,
- mode plein écran support,
- page Authentication + récupération mot de passe.

## 9) Limites actuelles et évolutions

### Limites (version prototype)

- Données utilisateurs simulées en mémoire.
- Session streaming simulée (pas de flux vidéo réel backend).
- Pas de persistance serveur ni authentification centralisée.

### Évolutions proposées

- Backend réel (API + base de données).
- WebSocket/WebRTC pour session temps réel.
- Journalisation/traçabilité des sessions.
- Gestion avancée des permissions et audit sécurité.
