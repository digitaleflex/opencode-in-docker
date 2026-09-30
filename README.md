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

Puis relancer. Le projet est monté dans `/projects/<nom-du-dossier>`
(aussi le `working_dir` du conteneur — c'est ce nom que le TUI affiche).

> ⚠️ **Perf — coût mesuré du montage Windows.** Mesuré dans le conteneur
> (500 fichiers créés puis lus, timer `EPOCHREALTIME`) :
>
> | Chemin | Écriture 500 | Lecture 500 |
> |---|---|---|
> | `/projects/workspace` (bind-mount Windows) | **9 349 ms** | **3 018 ms** |
> | `/tmp` (Linux natif) | 92 ms | 9 ms |
> | volume `oc-data` (Docker) | 106 ms | 8 ms |
>
> → **~100× en écriture**, **~350× en lecture** sur du travail à petits
> fichiers (git, `node_modules`, lint). Trois leviers :
>
> 1. **Serveur long-lived** — `docker compose up -d` supprime les 3-5 s de
>    démarrage par session (livré, `compose.serve.yml`).
> 2. **Monter le projet depuis WSL** — `PROJECT_DIR=\\wsl$\<distro>\…` ou
>    lancer depuis WSL. Nécessite l'intégration WSL de Docker Desktop
>    (aujourd'hui `EnableIntegrationWithDefaultWslDistro: false`, et
>    l'erreur `distro-services/ubuntu.sock` en cas d'essai).
> 3. **Garder l'état dans les volumes nommés** — `oc-data`, `oc-cache` et
>    `oc-config` sont déjà en Linux natif.
>
> Copier le projet dans `workspace/` **n'apporte rien** : c'est le même type
> de montage Windows.

## Instructions de l'agent (AGENTS.md)

La config charge deux emplacements, **relatifs au dossier ouvert** :

```json
"instructions": ["AGENTS.md", ".rules/*.md"]
```

| Entrée | Rôle | Sans fichier |
|---|---|---|
| `AGENTS.md` | description du projet : stack, commandes réelles, architecture, conventions | l'agent travaille à l'aveugle |
| `.rules/*.md` | règles découpées (sécurité, style…) | ignoré silencieusement |

**Chaque projet ouvert avec OpenCode doit avoir son propre `AGENTS.md` à la
racine**, versionné dans son dépôt. Le `workspace/AGENTS.md` livré ici ne
décrit que le bac à sable monté par défaut ; il est remplacé dès que
`PROJECT_DIR` pointe ailleurs.

> Vérifier ce qui est réellement chargé : le conteneur doit voir le fichier
> dans `/projects/<nom-du-dossier>/AGENTS.md`.

## Subagents & parallélisme

### Agents disponibles (vérifié sur 2.0.18)

| Agent | Type | Usage |
|---|---|---|
| `build` | primaire | défaut, bascule avec **Tab** |
| `plan` | primaire | analyse lecture seule, **Tab** |
| `general` | subagent | `@general …` |
| `explore` | subagent | `@explore …` (lecture seule) |
| `review` | subagent | `@review …` (relecture, cf. `config/agents/`) |
| `compaction`, `title`, `summary` | système | automatiques, masqués |

`scout`, cité dans la documentation officielle, **n'existe pas en 2.0.18**.

Contrôle : `GET /api/agent` sur le serveur (8 agents). Attention :
`opencode debug agents` ne liste que les agents **personnalisés** et affiche
`[]` tant que vous n'en avez pas créé.

### Parallélisme

Le modèle peut enchaîner plusieurs appels `task` dans un même tour : les
subagents tournent alors **concurremment**, pas l'un après l'autre.

Vérifié : deux subagents `explore` lancés depuis la même session parent ont
terminé à **83 ms** d'intervalle (sessions enfants de même parent).

> ⚠️ **Coût** : chaque subagent = session enfant = requêtes supplémentaires.
> Deux appels simultanés **doublent le débit** — sur un modèle gratuit
> (`:free`), c'est le chemin direct vers un `429`. En cas de coupure :
> `/models` pour changer de modèle **en conservant la conversation**.

### Navigation entre sessions (documentation officielle)

| Raccourci | Action |
|---|---|
| `Leader` + `↓` | entrer dans la première session enfant |
| `←` / `→` | circuler entre sessions enfants |
| `↑` | revenir à la session parent |

> Raccourcis issus de la doc OpenCode — à confirmer dans le TUI via la
> palette de commandes.

## Ce qui est isolé

| Host | Conteneur | Type |
|---|---|---|
| `./config/opencode.json` | `/config/opencode.json` | bind, **lecture seule** |
| `./workspace` (ou `PROJECT_DIR`) | `/projects/<nom-du-dossier>` | bind, RW |
| — | `/home/opencode/.local/share/opencode` | volume `oc-data` (sessions + base SQLite) |
| — | `/home/opencode/.cache/opencode` | volume `oc-cache` (plugins npm) |
| — | `/home/opencode/.config/opencode` | volume `oc-config` (config globale, **auth**, agents) |
| `.env` (clés API) | injecté à l'exécution | `env_file`, jamais dans l'image |

Rien d'autre du host n'est visible depuis le conteneur. Les credentials
OpenCode Console sont dans `oc-config/service.json` (pas dans `oc-data`).

## Sécurité (état réel)

Trois couches, de la plus structurelle à la plus souple :

**1. Le conteneur — la vraie barrière.** Seuls les montages ci-dessus sont
accessibles, sous Alpine, sans aucun accès au reste du host.

**2. L'utilisateur.** `uid=1000(opencode)`, jamais root au démarrage.
`no-new-privileges` est **volontairement absent** (`security_opt: []`) :
il bloquerait l'escalade `sudo` dont le Dockerfile dote le compte.
L'isolation ne repose donc **pas** sur les permissions OpenCode.

**3. Les permissions OpenCode (`config/opencode.json`).** Mode permissif par
défaut, avec des denys ciblés :

| Clé | Valeur | Effet |
|---|---|---|
| `"*"` | `allow` | tout est autorisé sans demande (mode agent) |
| `bash` | 9 × `deny` | `rm -rf /*`, `rm -rf ~*`, `/home*`, `/root*`, `..*`, `mkfs*`, `dd *`, **`sudo *`**, fork-bomb |
| `read` | `deny` sur `*.env` / `*.env.*` | l'agent ne lit pas tes clés (`.env.example` reste lisible) |
| `task` | `allow` | subagents autorisés |
| `external_directory`, `webfetch`, `websearch`, `doom_loop` | `ask` | validation humaine |

> ⚠️ **Limites assumées.** Les règles `bash` sont des **matchs de chaîne** :
> `rm -fr`, `bash -c "…"`, `command rm` les contournent. Ce sont des
> garde-fous, pas une sandbox — la sécurité vient du point 1.
> Vérifier la config réellement résolue :
> `docker compose run --rm opencode debug config`.

Aussi en place :

- **Config montée en lecture seule** : l'agent ne peut pas modifier sa propre config
- **`share: "disabled"`** + **`autoupdate: false`** : rien ne sort, rien ne se met à jour seul
- **Clés hors image** : `.env` est gitignoré (vérifié : `git check-ignore`), injecté au runtime uniquement

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
| **agent** (défaut) | `opencode` (uid 1000) | tout `allow` dans OpenCode, **mais `"sudo *": "deny"`** | sessions normales |
| **root** | `root` | `docker compose run --rm --user root opencode …` | opérations système |

Deux niveaux à ne pas confondre :

- **Niveau OS** : `sudoers.d/opencode` donne `NOPASSWD:ALL`. **Testé** :
  `sudo id`, `sudo -n true`, `sudo -i id` → tous root OK.
- **Niveau agent OpenCode** : `config/opencode.json` pose `"sudo *": "deny"` —
  l'agent ne peut **pas** s'élever. C'est volontaire : root ne s'obtient
  qu'en dehors de l'agent, au lancement du conteneur.

Autres points :

- `no-new-privileges` retiré volontairement (bloquerait l'escalade) — cf. *Sécurité*
- Isolation = conteneur + seuls montages, **pas** les permissions OpenCode — idem
- Identité git système : `opencode-agent <agent@opencode.local>` + `safe.directory *`

## Persistance (survit aux redémarrages)

| Donnée | Volume | Survit à `down` | Survit à `down -v` | Survit à redémarrage PC |
|---|---|---|---|---|
| Sessions + base SQLite | `oc-data` | ✅ | ❌ | ✅ |
| Plugins npm | `oc-cache` | ✅ | ❌ | ✅ |
| Config globale, **auth**, agents | `oc-config` | ✅ | ❌ | ✅ |
| Config (host) | `./config/` | ✅ | ✅ | ✅ |
| Projet | `${PROJECT_DIR}` | ✅ | ✅ | ✅ |

Volumes nommés Docker = persistants par nature. Seul `down -v` les supprime.
Testé : marqueur écrit → `down` → volumes intacts → marqueur relu ✅.

Lancement par répertoire : le wrapper `opencode.bat` capture `%CD%` →
monté dans `/projects/<nom-du-dossier>` (testé depuis un repo GitHub ✅).

## Dépannage

| Symptôme | Cause | Solution |
|---|---|---|
| `«opencode» n'est pas reconnu` | PATH pas rechargé après création du wrapper | Ouvre un **nouveau** terminal, ou `refreshenv` |
| `the input device is not a TTY` | flag `-it` lancé sans terminal interactif | Le wrapper utilise `docker compose` (auto-TTY) — utilise `opencode.bat`, pas `docker run -it` à la main |
| Le dossier affiché n'est pas le bon | wrapper lancé sans `cd` préalable | `cd` d'abord puis `opencode` : c'est `%CD%` qui est monté |
| `Cannot connect to the Docker daemon` | Docker Desktop fermé | Lance Docker Desktop |
