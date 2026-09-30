# AGENTS.md — dossier bac à sable

## Vue d'ensemble

- **Type** : dossier de travail **vide**, monté par défaut dans le conteneur
- **Stack** : aucune — aucun paquet, aucun code, aucun dépôt
- **Objectif** : servir de cible neutre quand aucune variable `PROJECT_DIR`
  n'est définie dans `.env`

Ce dossier ne contient que ce fichier et `.ignore`.

## Ce qu'il faut faire

1. **Renseigner ton vrai projet** dans `.env` :
   ```powershell
   PROJECT_DIR=C:\Users\PC\Documents\GitHub\mon-projet
   ```
   Il sera monté dans `/projects/<nom-du-dossier>` et deviendra le répertoire
   de travail — c'est alors **son** `AGENTS.md` qui sera lu (voir ci-dessous).

2. **Créer un `AGENTS.md` à la racine de chaque projet** que tu ouvres avec
   OpenCode. C'est le fichier qui décrit au taux d'agent :
   - le type de projet et la stack réelle
   - les commandes qui **existent** (install, dev, test, lint, build)
   - l'architecture (point d'entrée, dossiers clés)
   - les conventions et les règles applicables

## Instructions chargées

La config charge, **par rapport au dossier ouvert** :

```json
"instructions": ["AGENTS.md", ".rules/*.md"]
```

- `AGENTS.md` : obligatoire pour tout projet sérieux — à versionner dans le
  dépôt du projet
- `.rules/*.md` : emplacement optionnel pour des règles découpées
  (ex. `.rules/securite.md`, `.rules/style.md`) ; ignore silencieusement
  s'il n'existe pas

## Règles pour l'agent

- **Toujours** :
  - lire un fichier avant de le modifier
  - garder les diffs petits et ciblés
  - s'arrêter et demander si le projet réel ne correspond pas à ce qui est
    décrit ici
- **Jamais** :
  - inventer des commandes qui n'existent pas dans le projet
  - modifier `.env` ni toucher aux clés
  - désactiver des tests pour faire passer une validation

## Validation (definition of done)

1. Les commandes annoncées passent réellement
2. Aucune modification hors périmètre demandé
3. Les changements d'architecture sont reflétés dans le `AGENTS.md` du projet
