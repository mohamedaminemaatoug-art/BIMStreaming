# BimStreaming — Logique applicative

## Vue d'ensemble

BimStreaming est une application desktop Windows (Flutter) qui combine :
- messagerie en temps réel (DM + communautés)
- gestion de contacts (amis, présence)
- support à distance (partage d'écran, clavier/souris, transfert de fichiers)

La communication temps réel passe par WebSocket ; la vidéo de partage d'écran utilise le codec VP9 via FFI Win32 + WebRTC.

---

## Écrans principaux (ordre logique d'utilisation)

---

### 1. Écran de connexion (`/auth/login`)

**Ce que fait cet écran**
Point d'entrée de l'application. L'utilisateur s'authentifie avec son identifiant (nom d'utilisateur ou e-mail) et son mot de passe.

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Se connecter | Envoie les identifiants au serveur via `POST /auth/login` |
| Mot de passe oublié | Ouvre le formulaire de récupération |
| S'inscrire | Redirige vers l'assistant d'inscription |

**Transitions**
- Connexion réussie sans 2FA → **Accueil** (`/app/home`)
- Connexion réussie avec 2FA activé → **Vérification 2FA** (`/auth/2fa`)
- Clic "Mot de passe oublié" → **Mot de passe oublié** (`/auth/forgot`)
- Clic "S'inscrire" → **Inscription** (`/auth/register`)

---

### 2. Écran d'inscription (`/auth/register`)

**Ce que fait cet écran**
Assistant d'inscription en 3 étapes (Stepper) :
1. **Identité** — nom complet, nom d'utilisateur
2. **Sécurité** — mot de passe
3. **Contact** — adresse e-mail

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Suivant / Précédent | Navigation entre les étapes |
| Terminer | Soumet l'inscription via `POST /auth/register` |

**Transitions**
- Inscription réussie (sans 2FA) → **Accueil** (`/app/home`)
- Inscription avec 2FA → **Vérification 2FA** (`/auth/2fa`)

---

### 3. Vérification 2FA (`/auth/2fa`)

**Ce que fait cet écran**
Saisie d'un code à 6 chiffres envoyé par e-mail ou application TOTP, requis si l'utilisateur a activé l'authentification à deux facteurs.

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Valider le code | Envoie le code via `POST /auth/2fa` |
| Renvoyer le code | Redemande un code au serveur |

**Transitions**
- Code valide → **Accueil** (`/app/home`)
- Retour → **Connexion** (`/auth/login`)

---

### 4. Récupération de mot de passe (`/auth/forgot` → `/auth/reset-code` → `/auth/new-password`)

**Ce que font ces écrans**
Flux en trois étapes :
1. `/auth/forgot` — saisie de l'adresse e-mail
2. `/auth/reset-code?email=…` — saisie du code de vérification reçu par e-mail
3. `/auth/new-password?code=…` — saisie du nouveau mot de passe

**Actions disponibles**
| Étape | Action |
|-------|--------|
| Mot de passe oublié | Soumettre l'e-mail |
| Code de réinitialisation | Valider le code |
| Nouveau mot de passe | Définir et confirmer le nouveau mot de passe |

**Transitions**
- Flux terminé → **Connexion** (`/auth/login`)

---

### 5. Accueil — Tableau de bord & Support distant (`/app/home`)

**Ce que fait cet écran**
Page principale après connexion. Affiche l'identité du poste local et permet d'initier ou de recevoir des sessions de support à distance.

**Informations affichées**
- ID de l'appareil (copiable dans le presse-papier)
- Mot de passe de session
- Indicateur de statut en ligne (vert = connecté, gris = hors ligne)
- Tableau de l'historique des sessions récentes (utilisateur cible, ID appareil, type, durée, statut, date)

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Copier l'ID appareil | Copie l'identifiant dans le presse-papier |
| Envoyer une invitation | Saisir l'ID appareil cible + mot de passe → envoie une demande de connexion distante |
| Accepter une invitation | (Pop-up de 2 minutes) — accepte la demande entrante |
| Refuser une invitation | Rejette la demande entrante |

**Transitions**
- Invitation acceptée (côté initiateur ou récepteur) → **Support distant** (page modale, `Navigator.push`)
- Clic sur un item de la barre latérale → écrans correspondants

---

### 6. Support distant (page modale — `remote_support_page.dart`)

**Ce que fait cet écran**
Session de contrôle à distance temps réel entre deux postes Windows. Utilise :
- Capture d'écran DXGI (Win32/FFI)
- Encodage/décodage VP9
- Signalisation WebRTC via WebSocket
- Transmission d'événements clavier et souris
- Transfert de fichiers

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Contrôle clavier/souris | Envoie les événements de saisie à la machine distante |
| Transfert de fichier | Envoie ou reçoit des fichiers pendant la session |
| Terminer la session | Déconnecte WebRTC et ferme la page |

**Transitions**
- Session terminée → retour à **Accueil** (`/app/home`)

---

### 7. Profil (`/app/profile` ou `/app/profile/:userId`)

**Ce que fait cet écran**
Affiche et modifie le profil utilisateur (le sien ou celui d'un autre utilisateur).

**Informations affichées**
- Avatar, nom d'affichage, e-mail, bio
- Emoji de statut, message de statut
- Badge de disponibilité (en ligne / absent / occupé / hors ligne)

**Actions disponibles (profil propre)**
| Action | Description |
|--------|-------------|
| Modifier la bio | Champ texte modifiable |
| Changer l'avatar | Sélection d'image via `file_picker`, upload multipart |
| Enregistrer le profil | `PATCH /profile` |
| Modifier le statut | Emoji + message + disponibilité → `PATCH /status` |

**Actions disponibles (profil d'un autre utilisateur)**
| Action | Description |
|--------|-------------|
| Envoyer une demande d'amis | Bouton dédié |
| Envoyer un message | Ouvre la conversation DM |

**Transitions**
- Clic "Envoyer un message" → **Messages** (`/app/messages/:userId`)

---

### 8. Amis (`/app/friends`)

**Ce que fait cet écran**
Gestion des contacts avec 3 onglets :

| Onglet | Contenu |
|--------|---------|
| Amis | Liste des amis avec avatar, nom, heure de dernière connexion, pastille de présence |
| Demandes | Demandes entrantes avec boutons accepter / refuser |
| Bloqués | Utilisateurs bloqués avec bouton débloquer |

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Rechercher un utilisateur | Dialogue de recherche (champ texte + résultats) |
| Envoyer une demande d'amis | Depuis le dialogue de recherche |
| Accepter / Refuser | Sur les demandes entrantes |
| Supprimer un ami | Menu contextuel sur la liste |
| Bloquer un utilisateur | Menu contextuel sur la liste |
| Débloquer | Sur l'onglet Bloqués |

**Événements temps réel**
- `friend:request` → nouvelle demande entrante (notification en direct)
- `user:online` / `user:offline` → mise à jour de la pastille de présence

**Transitions**
- Clic sur un ami → **Profil** (`/app/profile/:userId`)
- Clic "Envoyer un message" → **Messages** (`/app/messages/:userId`)

---

### 9. Messages (`/app/messages`)

**Ce que fait cet écran**
Liste de toutes les conversations directes (DM) de l'utilisateur.

**Informations affichées**
- Aperçu du dernier message
- Heure du dernier message
- Badge de messages non lus
- Indicateur "en train d'écrire…"

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Ouvrir une conversation | Clic sur une ligne → conversation complète |
| Rafraîchir | Bouton de rechargement de la liste |

**Transitions**
- Clic sur une conversation → **Conversation DM** (`/app/messages/:userId`)

---

### 10. Conversation DM (`/app/messages/:userId`)

**Ce que fait cet écran**
Fil de messages avec un utilisateur précis.

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Envoyer un message | Champ texte + bouton envoyer |
| Indicateur de frappe | Envoi automatique de `dm:typing` / `dm:typing_stop` |
| Modifier un message | Menu contextuel sur son propre message |
| Supprimer un message | Menu contextuel sur son propre message |
| Marquer comme lu | Automatique à l'ouverture de la conversation |

**Événements temps réel**
- `dm:new` → nouveau message ajouté en direct
- `dm:typing` / `dm:typing_stop` → affichage de l'indicateur

**Transitions**
- Retour → **Messages** (`/app/messages`)
- Clic sur l'avatar → **Profil** (`/app/profile/:userId`)

---

### 11. Communautés (`/app/communities`)

**Ce que fait cet écran**
Liste des communautés dont l'utilisateur est membre.

**Informations affichées**
- Icône, nom, nombre de membres de chaque communauté

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Rejoindre par code | Dialogue → saisie du code d'invitation |
| Rejoindre par ID | Dialogue → saisie de l'ID de la communauté |
| Créer une communauté | Dialogue → nom, description, public/privé |

**Transitions**
- Clic sur une communauté → **Détail de la communauté** (`/app/communities/:communityId`)

---

### 12. Détail d'une communauté (`/app/communities/:communityId`)

**Ce que fait cet écran**
Espace de discussion et d'administration d'une communauté.

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Envoyer un message | Dans le canal de la communauté |
| Voir les membres | Liste des membres avec rôles |
| Gérer les membres | (Admin) — promouvoir, retirer, mettre à jour |
| Gérer les départements | (Admin) — créer, modifier, supprimer |
| Générer un lien d'invitation | Partager un code d'accès |
| Ajouter un membre par e-mail | (Admin) |
| Quitter la communauté | |
| Paramètres | (Admin) → **Paramètres de la communauté** (`/app/communities/settings`) |

**Transitions**
- Retour → **Communautés** (`/app/communities`)
- Paramètres → **Paramètres de la communauté**

---

### 13. Notifications (`/app/notifications`)

**Ce que fait cet écran**
Centre de notifications de l'utilisateur.

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Marquer une notification comme lue | Clic sur la notification |
| Tout marquer comme lu | Bouton global |

**Événements temps réel**
- `notification:new` → nouvelle notification ajoutée en direct avec badge mis à jour

---

### 14. Paramètres (`/app/settings`)

**Ce que fait cet écran**
Configuration personnelle de l'application.

**Actions disponibles**
| Action | Description |
|--------|-------------|
| Basculer thème sombre/clair | Toggle |
| Changer la langue | Menu déroulant |
| Notifications bureau | Toggle |
| Notifications e-mail | Toggle |
| Notifications push | Toggle |
| Changer le mot de passe | Formulaire (mot de passe actuel + nouveau) |

---

## Carte des transitions globales

```
[Connexion] ──────────────────────────────────────────────────────────┐
     │ sans 2FA                                                        │
     ▼                                                                 │
[Accueil] ←──────────────── Barre latérale ──────────────────────────►│
     │                           │                                     │
     │ invitation envoyée/reçue  │                                     │
     ▼                           │                                     │
[Support distant] ──── fin ──►[Accueil]                               │
                                 │                                     │
               ┌─────────────────┼──────────────────────┐             │
               ▼                 ▼                      ▼             │
          [Amis]          [Messages]             [Communautés]        │
            │                  │                      │               │
            │                  ▼                      ▼               │
            │          [Conversation DM]   [Détail communauté]        │
            │                  │                      │               │
            └──────────────────┴──────[Profil]────────┘               │
                                                                       │
[Inscription] ──────────────────────────────────────────────────────►[Accueil]
[2FA] ──────────────────────────────────────────────────────────────►[Accueil]
[Récup. mot de passe] ──────────────────────────────────────────────►[Connexion]
```

---

## Flux de session à distance (détail)

```
Initiateur                        Récepteur
    │                                 │
    │── Saisie ID + MDP ─────────────►│
    │                                 │ Pop-up (2 min)
    │◄── remote:invite_accepted ──────│ Accepter
    │                                 │
    │── [WebRTC SDP + ICE] ──────────►│
    │◄──────────────────── [WebRTC] ──│
    │                                 │
    │════ Session VP9 active ═════════│
    │ (frames + clavier/souris/fich.) │
    │                                 │
    │── Déconnexion ─────────────────►│
```

---

## Rôles WebSocket

| Événement | Écran récepteur |
|-----------|----------------|
| `dm:new` | Messages / Conversation DM |
| `dm:typing` / `dm:typing_stop` | Conversation DM |
| `notification:new` | Notifications (badge global) |
| `user:online` / `user:offline` | Amis (pastille de présence) |
| `friend:request` | Amis (onglet Demandes) |
| `remote:invite` | Accueil (pop-up d'invitation) |
| `remote:invite_accepted` / `remote:invite_rejected` | Accueil (lancement ou annulation de session) |
