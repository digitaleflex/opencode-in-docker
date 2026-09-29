# Image de base : OpenCode v2.0.18 (tag épinglé = builds reproductibles)
# Alpine minimaliste (~74 Mo) — pas de runtime Windows dans le conteneur.
FROM ghcr.io/anomalyco/opencode:2.0.18

USER root

# Outils indispensables pour un agent de code :
#  - git       : commits + snapshots d'undo d'OpenCode
#  - bash      : shell des outils (l'image n'a que /bin/sh)
#  - curl      : appels réseau / healthchecks
#  - openssh   : push git
#  - nodejs    : plugins & LSP npm
#  - sudo      : passage root sans mot de passe (rôles ci-dessous)
RUN apk add --no-cache \
      git \
      bash \
      curl \
      openssh-client \
      nodejs \
      npm \
      tzdata \
      sudo

# --- Rôles ---
#  opencode (uid 1000) : rôle "agent" — tout en allow dans OpenCode,
#                        sudo NOPASSWD pour les opérations système.
#  root               : rôle "admin"  — `sudo -i` (aucun mot de passe).
RUN adduser -D -u 1000 opencode \
 && echo 'opencode ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/opencode \
 && chmod 0440 /etc/sudoers.d/opencode \
 && mkdir -p \
      /home/opencode/.config/opencode \
      /home/opencode/.local/share/opencode \
      /home/opencode/.cache/opencode \
      /work \
 && chown -R opencode:opencode /home/opencode /work

# Identité git locale dans le conteneur (le .gitconfig hôte est optionnel)
RUN git config --system safe.directory '*' \
 && git config --system user.name "opencode-agent" \
 && git config --system user.email "agent@opencode.local"

USER opencode
ENV HOME=/home/opencode
WORKDIR /work

ENTRYPOINT ["opencode"]
