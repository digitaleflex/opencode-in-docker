# OpenCode en Docker

OpenCode isolé dans un conteneur : rien n'atteint le host, purge en 1 commande.

## Prérequis

- Docker Desktop + WSL2 (déjà installé : Docker 29.6.2, Compose v5.3.1)

## Démarrage

### Depuis n'importe quel dossier (wrapper global) ✅

`opencode` et `oc` sont disponibles dans **tout le système** via
`C:\Users\PC\bin\` (déjà dans le PATH). Le répertoire courant devient
le working directory du conteneur :

```powershell
cd C:\Users\PC\Documents\GitHub\mon-projet
opencode            # TUI sur ce projet
opencode run "..."  # one-shot
oc                  # alias court
```

> Ancien comportement : avant la purge, `oc.bat` pointait vers l'install
> native. Il redirige maintenant vers le wrapper Docker.

### Depuis le dossier du projet (compose)

```powershell
cd C:\Users\PC\opencode-docker

# 1. Clés API (une fois) — copier puis remplir
copy .env.example .env
notepad .env

# 2. TUI interactif
docker compose run --rm opencode

# 3. One-shot (prompt unique)
docker compose run --rm opencode run "explique ce projet"

# 4. Serveur long-lived (http://localhost:4096) — service par défaut
#    Une seule instance qui vit en continu : plus de conteneur recréé
#    à chaque session = pas de coupure en cours de génération.
docker compose up -d               # démarrage
docker compose ps                  # état
docker compose down                # arrêt (conserve les volumes)
```

## Monter un vrai projet

Dans `.env` :

```powershell
PROJECT_DIR=C:\Users\PC\Documents\GitHub\mon-projet
```

Puis relancer. Le projet est monté dans `/work` (répertoire de travail du conteneur).

> ⚠️ Perf WSL2 : les bind-mounts Windows sont plus lents en IO. Pour du lourd,
> copie le projet dans `workspace/` (volume local) ou travaille depuis WSL.

## Ce qui est isolé

| Host | Conteneur | Type |
|---|---|---|
| `./config/opencode.json` | `/config/opencode.json` | bind, **lecture seule** |
| `./workspace` (ou `PROJECT_DIR`) | `/work` | bind, RW |
| — | `/home/opencode/.local/share/opencode` | volume nommé `oc-data` (sessions + auth) |
| — | `/home/opencode/.cache/opencode` | volume nommé `oc-cache` (plugins) |
| `.env` (clé API) | injecté à l'exécution | `env_file`, jamais dans l'image |

Rien d'autre du host n'est visible depuis le conteneur.

## Sécurité (bonnes pratiques appliquées)

- **Utilisateur non-root** : `uid=1000(opencode)` (l'image officielle tourne en root)
- **`no-new-privileges`** : pas d'élévation de privilèges possible
- **Permissions strictes** via `config/opencode.json` :
  - `"*": "ask"` → chaque action demande validation
  - whitelist : `git status/diff/log`, `npm test`, `rg`, `ls`, `cat`
  - `deny` : `rm -rf *`, `sudo *`, tout accès hors `/work` (`external_directory`)
- **Config en lecture seule** : l'agent ne peut pas se modifier sa propre config
- **`share: "disabled"`** + **`autoupdate: false`** : rien ne sort, rien ne se met à jour tout seul
- **Clés hors image** : `.env` est gitignoré, injecté au runtime uniquement

## Purge totale

```powershell
# Arrêt + suppression de TOUT (volumes = historique + auth + cache)
docker compose down -v

# Supprimer aussi l'image
docker compose down -v --rmi local
```

C'est tout. Contrairement à l'install native, il n'y a **aucune trace** ailleurs
(pas de registre, de raccourcis, de tâches planifiées, de `~/.config`).

## Arborescence

```
opencode-docker/
├── Dockerfile            # image de base + git/bash/node, user non-root
├── compose.yml           # point d'entrée : include + volumes partagés
├── compose.base.yml      # service opencode (TUI / one-shot, profil "tui")
├── compose.serve.yml     # service opencode-serve (long-lived, port 4096)
├── config/
│   └── opencode.json     # permissions strictes (montée en RO)
├── .env                  # tes clés (gitignoré)
├── .env.example
├── .gitignore
├── workspace/            # projet monté par défaut
└── README.md
```

## Commandes utiles

```powershell
docker compose build              # reconstruire après modif du Dockerfile
docker compose down               # arrêter (conserve les volumes)
docker compose down -v            # arrêter + purger l'état
docker compose run --rm opencode debug config   # vérifier la config résolue
docker compose run --rm opencode debug agents   # agents/subagents résolus
docker compose logs               # logs

# Serveur long-lived (service par défaut du projet)
docker compose up -d               # démarrer / recréer le serveur
docker compose ps                  # état
docker compose logs -f opencode-serve
```

## Plugins globaux

Installés via `opencode plugin add` dans la config **globale** du conteneur
(`~/.config/opencode/opencode.json`, volume `oc-config` = persistant).

```powershell
# Installer un plugin global (persiste dans le volume oc-config)
docker compose run --rm opencode plugin add <nom>@<version>

# Lister — note : ne montre que les plugins à fonction TUI chargés pour cwd
docker compose run --rm opencode plugin list
```

**État actuel (testé sur 2.0.18) :**

| Plugin | État | Raison |
|---|---|---|
| `@tarquinen/opencode-dcp@3.2.0` | ✅ **chargé** | Compatible API v2 (pruning des sorties d'outils = économie de tokens) |
| `opencode-vibeguard@0.1.0` | ❌ rejeté | API v1 : pas d'`export default { id, effect/setup }` |
| `opencode-command-inject@1.3.1` | ❌ rejeté | API v1 : exports nommés uniquement |
| `opencode-autotitle@0.1.3` | ❌ rejeté | API v1 : `default` n'est pas un objet plugin |

> Les 3 rejets sont **silencieux** (WARN dans les logs, pas d'erreur CLI).
> Vérifier le chargement réel :
> `docker compose run --rm opencode run --auto "test"` puis inspecter
> le volume `oc-data` → `log/opencode.log` (grep `failed to load`).

> ⚠️ `plugin list` peut afficher « No plugins found » même quand un plugin
> charge correctement : la commande ne liste que les plugins **TUI** résolus
> pour le `cwd`. La source de vérité = `log/opencode.log`.

## Rôles & permissions

| Rôle | User | Accès | Usage |
|---|---|---|---|
| **agent** (défaut) | `opencode` (uid 1000) | YOLO : tout allow dans OpenCode | sessions normales |
| **root** | `root` | `sudo -i` / `sudo <cmd>` — **aucun mot de passe** | opérations système |
| **root direct** | `root` | `docker compose run --rm --user root opencode ...` | hors agent |

- `sudoers.d/opencode` : `NOPASSWD:ALL` (image Dockerfile)
- `no-new-privileges` **retiré volontairement** (il bloquerait sudo)
- Isolation = conteneur + `/work` monté uniquement — pas les permissions OpenCode
- Identité git système : `opencode-agent <agent@opencode.local>` + `safe.directory *`

**Testé** : `sudo id`, `sudo -n true`, `sudo -i id` → tous root OK.

## Persistance (survit aux redémarrages)

| Donnée | Volume | Survit à `down` | Survit à `down -v` | Survit à redémarrage PC |
|---|---|---|---|---|
| Sessions + auth | `oc-data` | ✅ | ❌ | ✅ |
| Plugins npm | `oc-cache` | ✅ | ❌ | ✅ |
| Config globale | `oc-config` | ✅ | ❌ | ✅ |
| Config (host) | `./config/` | ✅ | ✅ | ✅ |
| Projet | `${PROJECT_DIR}` | ✅ | ✅ | ✅ |

Volumes nommés Docker = persistants par nature. Seul `down -v` les supprime.
Testé : marqueur écrit → `down` → volumes intacts → marqueur relu ✅.

Lancement par répertoire : le wrapper `opencode.bat` capture `%CD%` →
monté dans `/work` du conteneur (testé depuis un repo GitHub ✅).

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `«opencode» n'est pas reconnu` | PATH pas rechargé après création du wrapper | Ouvre un **nouveau** terminal, ou `refreshenv` |
| `the input device is not a TTY` | flag `-it` lancé sans terminal interactif | Le wrapper utilise `docker compose` (auto-TTY) — utilise `opencode.bat`, pas `docker run -it` à la main |
| Le dossier affiché n'est pas le bon | wrapper lancé sans `cd` préalable | `cd` d'abord puis `opencode` : c'est `%CD%` qui est monté |
| `Cannot connect to the Docker daemon` | Docker Desktop fermé | Lance Docker Desktop |
