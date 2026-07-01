#!/usr/bin/env bash
#
# Drupal homelab deploy — runs ON the homelab host, invoked over SSH by
# .github/workflows/deploy.yml. Kept in git so it is reviewable and testable.
#
# Order of operations is deliberate and safety-first:
#   1. write .env for docker compose
#   2. build the new image (code + composer deps baked in)
#   3. BACK UP THE DATABASE before anything mutates it
#   4. bring containers up (never drops the DB volume or files mount)
#   5. run drush updb -> cim -> cr
#
# Required env vars (passed in by the workflow):
#   DB_NAME DB_USER DB_PASSWORD DB_ROOT_PASSWORD DRUPAL_HASH_SALT
# Optional:
#   DEPLOY_DIR   (default: this script's parent dir)
#   BACKUP_DIR   (default: $HOME/drupal-backups)
#   BACKUP_KEEP  (default: 10)

set -euo pipefail

# --- resolve paths --------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="${DEPLOY_DIR:-$(dirname "$SCRIPT_DIR")}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/drupal-backups}"
BACKUP_KEEP="${BACKUP_KEEP:-10}"

cd "$DEPLOY_DIR"

# --- require secrets ------------------------------------------------------
: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${DB_ROOT_PASSWORD:?DB_ROOT_PASSWORD is required}"
: "${DRUPAL_HASH_SALT:?DRUPAL_HASH_SALT is required}"

dc() { docker compose "$@"; }
# Run drush as www-data (so file ownership matches Apache) with a writable HOME,
# otherwise drush cannot write its cache/config and every invocation fails.
drush() { dc exec -T -u www-data -e HOME=/tmp drupal vendor/bin/drush "$@"; }

# --- 1. write .env --------------------------------------------------------
echo "📝 Writing .env..."
cat > .env <<ENVEOF
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
DB_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DRUPAL_HASH_SALT=${DRUPAL_HASH_SALT}
IS_DOCKER_DEPLOYMENT=true
ENVEOF

# --- 2. build new image ---------------------------------------------------
echo "🏗️  Building image..."
export BUILDKIT_PROGRESS=plain
dc build

# Make sure the DB container is up so we can back it up (it may be stopped on a
# first run). This does not touch the drupal container yet.
echo "🛢️  Ensuring database is running..."
dc up -d db

echo "⏳ Waiting for database to accept connections..."
for i in $(seq 1 30); do
  if dc exec -T db mysqladmin ping -u root -p"${DB_ROOT_PASSWORD}" --silent 2>/dev/null; then
    echo "✅ Database is ready."
    break
  fi
  [ "$i" -eq 30 ] && { echo "❌ Database did not become ready in time."; exit 1; }
  sleep 2
done

# --- 3. BACK UP THE DATABASE (before any migration) -----------------------
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/db-$(date +%Y%m%d-%H%M%S).sql.gz"
echo "💾 Backing up database to $BACKUP_FILE ..."
if dc exec -T db mysqldump -u root -p"${DB_ROOT_PASSWORD}" \
     --single-transaction --quick --skip-lock-tables \
     "${DB_NAME}" 2>/dev/null | gzip > "$BACKUP_FILE"; then
  # A gzip of an empty stream is ~20 bytes; anything smaller than 1KB is suspect.
  if [ "$(gzip -dc "$BACKUP_FILE" | head -c 1000 | wc -c)" -lt 100 ]; then
    echo "⚠️  Backup looks empty — this is likely a first deploy (empty DB). Continuing."
  else
    echo "✅ Backup written ($(du -h "$BACKUP_FILE" | cut -f1))."
  fi
else
  echo "❌ Database backup failed — aborting before any changes."
  rm -f "$BACKUP_FILE"
  exit 1
fi

# Prune old backups, keep the most recent $BACKUP_KEEP.
echo "🧹 Pruning old backups (keeping $BACKUP_KEEP)..."
ls -1t "$BACKUP_DIR"/db-*.sql.gz 2>/dev/null | tail -n +"$((BACKUP_KEEP + 1))" | xargs -r rm -f

# --- 4. Bring up the new app image. `up -d` recreates ONLY the containers whose
# definition changed — i.e. the app (new image each build). The DB container is
# NOT recreated (its image is unchanged), so MariaDB keeps running and does not
# repeat slow InnoDB recovery on every deploy. --remove-orphans cleans up any
# stale services. Data (DB volume + files mount) is preserved; we never use -v.
echo "🚀 Starting/updating containers (app gets the new image; DB stays up)..."
dc up -d --remove-orphans

# Readiness probe: drush must bootstrap Drupal with a working DB connection.
# `drush status` prints "Drupal bootstrap : Successful" once it's ready.
#
# NB: we capture the output and test it with a bash match instead of piping to
# `grep -q`. Under `set -o pipefail`, `grep -q` matches and closes the pipe,
# drush then dies with SIGPIPE, and pipefail makes the whole pipeline report
# failure — so the probe never detects success even though it matched.
echo "⏳ Waiting for Drupal to bootstrap..."
for i in $(seq 1 30); do
  status_out="$(drush status 2>/dev/null || true)"
  if [[ "$status_out" == *Successful* ]]; then
    echo "✅ Drupal bootstrapped."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "❌ Drupal did not bootstrap in time. drush status was:"
    printf '%s\n' "$status_out"
    dc logs --tail=50 drupal
    exit 1
  fi
  sleep 3
done

# --- runtime permissions: only the files mount needs fixing (baked image
#     already owns the code) --------------------------------------------------
echo "🔧 Fixing permissions on files mount..."
dc exec -T -u root drupal bash -c '
  if [ -d /var/www/html/web/sites/default/files ]; then
    chown -R www-data:www-data /var/www/html/web/sites/default/files
  fi
' || echo "⚠️  Permission fix skipped."

# --- 5. database updates + config import ----------------------------------
echo "🗄️  Running database updates..."
drush updb -y

# Import config only if we actually have committed config. Importing an empty
# sync dir would DELETE live config, so guard against it.
if [ -n "$(ls -A config/sync/*.yml 2>/dev/null || true)" ]; then
  echo "📥 Importing configuration..."
  drush cim -y
else
  echo "⏭️  No config/sync/*.yml found — skipping config import (not yet seeded)."
fi

echo "🧹 Rebuilding cache..."
drush cr

echo "✅ Deployment complete."
dc ps
