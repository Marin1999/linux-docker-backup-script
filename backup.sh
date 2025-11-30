#!/usr/bin/env bash
set -euo pipefail

#############################################
# 0. BASIC SETTINGS
#############################################

# Where all backups will be stored
BACKUP_BASE="/your/backups/path"

# Folders where your docker-compose projects live (edit these!)
PROJECT_DIRS=()

# MySQL / MariaDB containers to dump (optional)
MYSQL_CONTAINERS=()

POSTGRES_CONTAINERS=()

MYSQL_USER="your_root_user"
MYSQL_PASSWORD="your_root_password"

POSTGRES_USER="your_postgres_user"
POSTGRES_PASSWORD="your_postgres_password"


# How many days of backups to keep (set 0 to disable cleanup)
RETENTION_DAYS=30

#############################################
# 1. LOAD RESTIC ENV (Backblaze B2)
#############################################

RESTIC_ENABLED=false

RESTIC_ENV_PATH="/your/path/.restic-env"

if [ -f ${RESTIC_ENV_PATH} ]; then
  echo "Loading Restic environment from ~/.restic-env..."
  RESTIC_ENABLED=true
  set -a
  . "${RESTIC_ENV_PATH}"
  set +a
else
  echo "WARN: ~/.restic-env not found, Restic offsite backup will be skipped."
fi

#############################################
# 2. PREPARE BACKUP FOLDERS
#############################################

TS="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_BASE}/${TS}"

PROJECTS_BASE="${BACKUP_DIR}/projects"
DB_DUMP_DIR="${BACKUP_DIR}/db_dumps"

echo "Creating backup at: ${BACKUP_DIR}"
mkdir -p "${PROJECTS_BASE}" "${DB_DUMP_DIR}"


#############################################
# 2a. BACKUP PER-PROJECT CONFIGS (+ nginx + content)
#############################################

echo "Backing up docker-compose files and project configs..."
for dir in "${PROJECT_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    proj_name="$(basename "$dir")"
    proj_dir="${PROJECTS_BASE}/${proj_name}"
    proj_config_dir="${proj_dir}/configs"
    proj_env_dir="${proj_dir}/env_files"

    mkdir -p "$proj_config_dir" "$proj_env_dir"

    echo "== Project: ${proj_name} =="

    # Copy docker-compose.yml and any *.yml/yaml files
    find "$dir" -maxdepth 2 -type f \
      \( -name "docker-compose.yml" -o -name "*.yml" -o -name "*.yaml" \) \
      -exec cp {} "$proj_config_dir" \;

    # Copy known config-like subfolders if present
    # Includes 'content' so Ghost's content/ is backed up too
    for sub in config configs conf nginx content; do
      if [ -d "$dir/$sub" ]; then
        echo "  - copying ${sub} from ${dir}"
        cp -r "$dir/$sub" "$proj_config_dir/"
      fi
    done

    # Back up .env files for this project (keep them grouped per project)
    echo "  - copying .env files from ${dir}"
    find "$dir" -maxdepth 3 -type f -name ".env" -exec cp {} "$proj_env_dir" \;

  else
    echo "WARN: Project dir not found: $dir"
  fi
done

# Optional: remove any "logs" directories from copied configs to keep backups lean.
# If you decide you don't care about logs, you can comment this out.
echo "Removing logs directories from configs..."
find "${PROJECTS_BASE}" -type d -name logs -prune -exec rm -rf {} +



#############################################
# 3. BACKUP DATABASES
#############################################

# MySQL / MariaDB
if [ "${#MYSQL_CONTAINERS[@]}" -gt 0 ]; then
  echo "Dumping MySQL/MariaDB databases..."
  for c in "${MYSQL_CONTAINERS[@]}"; do
    echo "  - dumping from container: $c"
    OUT_FILE="${DB_DUMP_DIR}/mysql-${c}-${TS}.sql"

    if [ -n "$MYSQL_PASSWORD" ]; then
      docker exec "$c" sh -c \
        "mysqldump -u\"${MYSQL_USER}\" -p\"${MYSQL_PASSWORD}\" --all-databases" \
        > "$OUT_FILE"
    else
      docker exec "$c" sh -c \
        "mysqldump -u\"${MYSQL_USER}\" --all-databases" \
        > "$OUT_FILE"
    fi
  done
fi


# PostgreSQL
if [ "${#POSTGRES_CONTAINERS[@]}" -gt 0 ]; then
  echo "Dumping PostgreSQL databases..."
  for c in "${POSTGRES_CONTAINERS[@]}"; do
    echo "  - dumping from container: $c"
    OUT_FILE="${DB_DUMP_DIR}/postgres-${c}-${TS}.sql"

    docker exec "$c" sh -c \
      "PGPASSWORD=\"${POSTGRES_PASSWORD:-}\" pg_dumpall -U \"${POSTGRES_USER}\"" \
      > "$OUT_FILE"
  done
fi


#############################################
# 4. OFFSITE BACKUP WITH RESTIC (Backblaze B2)
#############################################



if [ "${RESTIC_ENABLED}" = true ]; then
  echo "=== Starting Restic backup to Backblaze B2 ==="
  echo "Backing up folder: ${BACKUP_DIR}"

  # Create a Restic snapshot of this specific backup folder
  restic backup "${BACKUP_DIR}" \
    --hostname "home-server" \
    --tag "docker-backup"

  echo "Applying Restic retention policy (7 daily, 4 weekly, 6 monthly)..."
  restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 6 \
    --prune

  echo "=== Restic backup completed ==="
else
  echo "Skipping Restic backup (RESTIC_ENABLED=false or ~/.restic-env missing)."
fi

#############################################
# 5. TAR + COMPRESS WHOLE BACKUP
#############################################

echo "Creating compressed archive..."
cd "${BACKUP_BASE}"
tar czf "${TS}.tar.gz" "${TS}"
# Optionally delete the uncompressed directory:
rm -rf "${BACKUP_DIR}"

#############################################
# 6. CLEANUP OLD BACKUPS
#############################################

if [ "$RETENTION_DAYS" -gt 0 ]; then
  echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
  find "${BACKUP_BASE}" -maxdepth 1 -type f -name "*.tar.gz" -mtime +"${RETENTION_DAYS}" -print -delete
fi

echo "✅ Backup completed: ${BACKUP_BASE}/${TS}.tar.gz"
