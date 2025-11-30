# Backup Script (Linux + Docker)

A simple backup script for Linux systems running Docker.  
It creates timestamped backups of your essential configuration and database data, and can optionally upload them to Backblaze B2 using Restic.

This script is designed to be easy to understand, easy to modify, and practical for small hobby servers.


## What this script does

- Collects `docker-compose.yml` files  
- Copies configuration folders (`config`, `configs`, `conf`, `content`, etc.)  
- Backs up `.env` files containing secrets  
- Creates MySQL/PostgreSQL database dumps  
- Stores everything in a clean timestamped directory  
- Optionally uploads the backup to Backblaze B2 using Restic  
- Cleans up old local backups based on retention settings

The goal is not to back up your entire server, but to save the most important pieces needed to rebuild your services quickly.


## What you need to configure

Edit `backup.sh` and update:

### `BACKUP_BASE`
Where your backups should be stored (an external disk is recommended).

### `PROJECT_DIRS`
Paths to your Docker project folders.

### `MYSQL_CONTAINERS` / `POSTGRES_CONTAINERS`
Container names for any databases you want to dump.

### Database credentials
Update the MySQL and Postgres username/password in the script.

### Retention
Adjust `RETENTION_DAYS` if needed.

### Restic setup
Create a file at `~/.restic-env` with your Backblaze B2 credentials.  
An example file is included:

```bash
cp .restic-env.example ~/.restic-env
chmod 600 ~/.restic-env
```


## Running the script

Run manually:

```bash
./backup.sh
```

Automate with cron:

```bash
0 3 * * 1 /path/to/backup.sh > /path/to/backup.log 2>&1
```

This runs the backup weekly and overwrites the log each time.
