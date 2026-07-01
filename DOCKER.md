# Deployment

This project runs Drupal 11 in Docker on a self-hosted homelab server. Deploys are
automated by `.github/workflows/deploy.yml`: on every push to `main`, GitHub Actions
connects to the server over Tailscale/SSH, syncs the repo, and runs `scripts/deploy.sh`.

## How it works

1. **Checkout & connect** — the runner joins the Tailnet and opens SSH to the homelab.
2. **Sync code** — `rsync` copies the repo to `~/drupal-deploy` on the host. This is the
   Docker **build context**; the code is *not* bind-mounted at runtime.
3. **`scripts/deploy.sh`** runs on the host and, in order:
   1. writes `.env` from the CI secrets,
   2. **builds the image** (code + `composer install` baked in — see `Dockerfile`),
   3. **backs up the database** to `~/drupal-backups/db-<timestamp>.sql.gz` *before* any
      migration, aborting the deploy if the dump fails (keeps the last 10),
   4. starts containers (`docker compose up -d` — never with `-v`, so data is preserved),
   5. runs `drush updb` → `drush cim` → `drush cr`.

Because the code is baked into the image and there is **no code volume**, a rebuilt image
is never shadowed by stale volume contents — what you push is what runs.

## Persistent data (never destroyed by a deploy)

| Data              | Location                                                        |
|-------------------|----------------------------------------------------------------|
| Database          | Docker volume `drupal_db_data`                                  |
| Uploaded files    | Host bind mount `/mnt/truenas/drupal-files` (TrueNAS)          |
| DB backups        | `~/drupal-backups/` on the host (last 10 kept)                 |

`docker compose down`/`up` and image rebuilds do **not** touch these. Only an explicit
`docker compose down -v` would drop the DB volume — the deploy script never does this.

## Configuration as code

Drupal configuration (enabled modules, theme selection, CKEditor/editor settings, etc.)
is versioned in `config/sync/` and imported on every deploy via `drush cim`.

- The sync directory is set in `web/sites/default/settings.php`:
  `$settings['config_sync_directory'] = '../config/sync';`
- **Export** local/live changes:  `drush config:export -y`  → commit `config/sync/`.
- **Import** happens automatically on deploy. The deploy script **skips** import when
  `config/sync/` has no `*.yml` (so an unseeded repo can't wipe live config).

Contrib modules and their versions are managed in `composer.json` / `composer.lock`.

## Prerequisites (one-time, on the host)

- Docker + Docker Compose.
- TrueNAS share mounted at `/mnt/truenas/drupal-files`.
- External network: `docker network create docker_net`.

## Environment variables (GitHub Secrets)

- `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_ROOT_PASSWORD`
- `DRUPAL_HASH_SALT` — the Drupal hash salt (keep stable across deploys)
- `HOMELAB_TAILSCALE_IP`, `HOMELAB_SSH_USER`, `HOMELAB_SSH_KEY`, `TAILSCALE_AUTHKEY`

## Local development

The project is DDEV-ready (`.ddev/`, `web/sites/default/settings.ddev.php`):

```bash
ddev start
ddev drush cim -y     # import committed config
```

Or run the production stack locally by copying `.env.example` to `.env` and
`docker compose up -d --build`.

## Common operations

```bash
docker compose logs -f drupal          # tail app logs
docker exec -it homesite bash          # shell into the app container
docker compose exec db mysql -u root -p # database shell

# Restore a backup (rollback):
gzip -dc ~/drupal-backups/db-YYYYmmdd-HHMMSS.sql.gz \
  | docker compose exec -T db mysql -u root -p"$DB_ROOT_PASSWORD" "$DB_NAME"
```

## Container structure

- **drupal** (`homesite`): PHP 8.3 + Apache, code + Composer deps baked into the image.
  Published on host port `8080` → container `80`.
- **db** (`drupal_db`): MariaDB 10.11, data in the `drupal_db_data` volume.
