# Tests et Évaluation — BimStreaming

## 1. Tests fonctionnels

### Authentification

| Cas de test | Résultat | Observations |
|---|---|---|
| Connexion sans 2FA | OK | Redirection immédiate vers `/app/home` après validation JWT |
| Connexion avec 2FA | OK | Code TOTP à 6 chiffres envoyé par e-mail, validé via `POST /auth/2fa` |
| Inscription (wizard 3 étapes) | OK | Identité → Sécurité → Contact ; compte créé et session ouverte automatiquement |
| Réinitialisation mot de passe | OK | Flux en 3 étapes : e-mail → code de vérification → nouveau mot de passe |

### Contrôle à distance

| Cas de test | Résultat | Observations |
|---|---|---|
| Envoi d'invitation | OK | Saisie ID appareil + mot de passe de session, invitation envoyée via WebSocket (`remote:invite`) |
| Acceptation d'invitation | OK | Pop-up côté récepteur (fenêtre de 2 minutes) ; acceptation déclenche la négociation WebRTC |
| Flux vidéo (partage d'écran) | OK | Capture DXGI + encodage VP9 ; flux stable à 30 FPS en conditions LAN |
| Injection clavier | OK | Événements transmis via canal WebRTC DataChannel ; disposition clavier préservée |
| Injection souris | OK | Position normalisée recalculée selon les dimensions réelles de l'écran distant ; canal curseur indépendant à ~166 Hz |
| Transfert de fichiers | OK | Protocole par blocs avec acquittement (`FILE_TRANSFER_CHUNK_ACK`) et vérification d'intégrité SHA-256 |
| Fin de session | OK | Déconnexion WebRTC + retour à `/app/home` des deux côtés |

### Messagerie

| Cas de test | Résultat | Observations |
|---|---|---|
| Envoi message DM | OK | Message transmis via WebSocket, persisté en base PostgreSQL |
| Réception message temps réel | OK | Événement `dm:new` reçu sans rechargement de page ; indicateur de frappe (`dm:typing`) fonctionnel |
| Indicateur de présence (online/offline) | OK | Pastille mise à jour en temps réel via `user:online` / `user:offline` |

### Communautés

| Cas de test | Résultat | Observations |
|---|---|---|
| Création de communauté | OK | Nom, description, visibilité (public/privé) configurables |
| Rejoindre via code d'invitation | OK | Code généré côté admin, saisi par le nouvel arrivant dans la boîte de dialogue dédiée |
| Envoi de message dans un canal | OK | Messages persistés et reçus en temps réel par tous les membres présents |

---

## 2. Résultats de performance

Les mesures ci-dessous ont été relevées en conditions LAN (commutateur Gigabit, même sous-réseau 192.168.1.x) avec une résolution source de 1920 × 1080.

| Indicateur | Valeur mesurée | Remarques |
|---|---|---|
| FPS affiché (côté contrôleur) | ~28–30 FPS | Cible configurée à 33 ms/frame (`_defaultCaptureIntervalMs`) |
| Latence aller-retour (ping WebSocket) | ~8–15 ms | En LAN Gigabit |
| Débit VP9 moyen | ~1 200–1 500 kb/s | Bitrate codé configuré à 1 500 kb/s (`bitrateKbps = 1500`) |
| Taux de perte de frames (Loss%) | < 1 % | Retransmission gérée par WebRTC SCTP DataChannel |
| Consommation CPU côté Agent | ~8–15 % | Capture DXGI GPU-accélérée (1–3 ms/frame) + VP9 DLL (2–5 ms/frame) |
| Résolution de capture transmise | 1 280 × 720 | Redimensionnement appliqué côté Agent (`_defaultCaptureMaxWidth = 1280`) |
| Conditions réseau du test | LAN Gigabit | Serveur et clients sur 192.168.1.x |

> **Note :** La latence d'encodage VP9 (2–5 ms/frame) représente une amélioration significative par rapport à l'ancienne voie JPEG (20–50 ms/frame) qui était le goulot d'étranglement précédent.

---

## 3. Limitations identifiées

1. **Windows uniquement** — La DLL native `bimstreaming_codec.dll` et l'API DXGI Desktop Duplication sont spécifiques à Windows ; aucun support Linux ou macOS.
2. **Audio distant non disponible** — La fonctionnalité est désactivée en dur (`_remoteAudioFeatureEnabled = false`) ; seule la vidéo est transmise.
3. **Moniteur unique** — Seul le moniteur principal (index 0) est capturé ; les configurations multi-écrans ne sont pas prises en charge.
4. **Taille de fichier limitée à 5 Mo** — La configuration serveur (`MAX_UPLOAD_SIZE_MB = 5`) restreint les transferts d'avatars et de pièces jointes.
5. **Résolution limitée à 1 280 px en largeur** — Le redimensionnement appliqué à la capture réduit la fidélité visuelle pour les écrans 2K/4K.
6. **Serveur non exposé sur Internet** — Le serveur écoute sur `192.168.1.100:8080` (adresse LAN) sans relais STUN/TURN ; les sessions à distance hors LAN nécessiteraient une configuration réseau supplémentaire (NAT traversal, VPN, reverse proxy).

---

## 4. Causes identifiées des limitations

| Limitation | Cause |
|---|---|
| Windows uniquement | Dépendance directe à `IDXGIOutputDuplication` (Win32) et à la DLL VP9 compilée pour Windows x64 |
| Absence d'audio | Intégration audio non finalisée dans le périmètre du projet ; la constante de désactivation est explicite dans le code |
| Moniteur unique | L'index de moniteur est fixé à 0 dans l'appel `DxgiCapturer.init()` ; aucune énumération dynamique des sorties DXGI |
| Limite de 5 Mo | Valeur codée dans `.env` côté serveur Go ; contrainte de stockage sur la machine de développement |
| Résolution plafonnée | Choix délibéré pour réduire la charge d'encodage et garantir un débit réseau maîtrisé à 1 500 kb/s |
| LAN uniquement | Absence de serveur STUN/TURN et d'exposition publique du backend (pas de nom de domaine, pas de reverse proxy) |

---

## 5. Pistes d'optimisation futures

1. **Portage multi-plateforme** — Remplacer DXGI par une API de capture cross-platform (ex. `screen_capturer`, PipeWire sur Linux, ScreenCaptureKit sur macOS) et compiler la DLL VP9 pour chaque cible.
2. **Transmission audio** — Intégrer un pipeline audio via WebRTC (Opus codec) en activant la branche déjà prévue dans le code.
3. **Support multi-moniteurs** — Énumérer les sorties DXGI disponibles et laisser l'Agent choisir ou l'opérateur sélectionner le moniteur à partager.
4. **Déploiement public avec TURN/STUN** — Intégrer un serveur Coturn et exposer le backend derrière un reverse proxy (Nginx / Caddy) avec TLS pour permettre les sessions hors LAN.
5. **Résolution adaptative** — Implémenter un mécanisme de bitrate adaptatif (ABR) qui ajuste dynamiquement `_captureMaxWidth` et `bitrateKbps` selon la bande passante mesurée.
6. **Compression des fichiers transférés** — Ajouter une compression LZ4/Zstd côté émetteur pour les transferts de fichiers volumineux.
7. **Encodage matériel** — Exploiter NVENC (NVIDIA) ou QuickSync (Intel) pour déléguer l'encodage VP9/AV1 au GPU et libérer le CPU.

---

## 6. Environnement de test

| Composant | Spécifications |
|---|---|
| Machine Agent (partageur d'écran) | Intel Core i5-10e gen, 16 Go RAM, GPU intégré Intel UHD |
| Machine Contrôleur (observateur) | Intel Core i3-8e gen, 8 Go RAM |
| Type de réseau | LAN Gigabit (commutateur 1 Gbit/s, même segment 192.168.1.x) |
| OS | Windows 11 Home (build 26200) sur les deux machines |
| Serveur applicatif | Go 1.22, PostgreSQL 15, adresse `192.168.1.100:8080` |
| Version testée | BimStreaming v1.2.0 |
