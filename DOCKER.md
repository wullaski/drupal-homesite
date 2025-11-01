# Docker Compose Deployment

This project uses Docker Compose to manage the Drupal application and MariaDB database containers.

## Prerequisites

- Docker and Docker Compose installed on your server
- TrueNAS share mounted at `/mnt/truenas/drupal-files`
- `docker_net` network created: `docker network create docker_net`


## Deployment

The GitHub Actions workflow automatically:
1. Builds the Docker image from the Dockerfile
2. Creates/updates containers via `docker-compose.yml`
3. Runs Composer install
4. Executes Drupal updates and configuration imports
5. Sets proper permissions

## Local Development

To run the stack locally:

1. Copy `.env.example` to `.env` and fill in your values:
   ```bash
   cp .env.example .env
   ```

2. Start the containers:
   ```bash
   docker-compose up -d
   ```

3. View logs:
   ```bash
   docker-compose logs -f
   ```

4. Stop containers:
   ```bash
   docker-compose down
   ```

## Container Structure

- **drupal** (`homesite`): PHP 8.2 + Apache with Drupal
  - Port: 80
  - Volume: `/opt/drupal` → `/var/www/html` (code)
  - Volume: `/mnt/truenas/drupal-files` (uploaded files)

- **db** (`drupal_db`): MariaDB 10.11
  - Volume: `drupal_db_data` (database storage)
  - Network: `docker_net`

## Environment Variables

Set these in GitHub Secrets:
- `DB_NAME`: Database name
- `DB_USER`: Database user
- `DB_PASSWORD`: Database password
- `DB_ROOT_PASSWORD`: Database root password
- `DRUPAL_HASH_SALT`: Auto-generated and persisted in `/opt/drupal/.hash_salt`

## Persistent Storage

- **Code**: `/opt/drupal` on host → `/var/www/html` in container (survives container recreation)
- **Uploaded Files**: `/mnt/truenas/drupal-files` (stored on TrueNAS)
- **Database**: Docker volume `drupal_db_data`
- **Hash Salt**: `/opt/drupal/.hash_salt` on host

## Troubleshooting

### View container logs
```bash
docker-compose logs drupal
docker-compose logs db
```

### Restart containers
```bash
docker-compose restart
```

### Rebuild containers
```bash
docker-compose up -d --build
```

### Access Drupal container shell
```bash
docker-compose exec drupal bash
```

### Access database
```bash
docker-compose exec db mysql -u root -p
```

## Benefits

✅ Infrastructure as Code - all config in version control  
✅ Easy local development - `docker-compose up`  
✅ Reproducible environments  
✅ Automated deployments  
✅ No manual Portainer configuration  
