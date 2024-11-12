#!/bin/bash

# Set backup directory and date
BACKUP_DIR="/path/to/local/backup_directory"
DATE=$(date +%Y-%m-%d)
BACKUP_FILE="backup_$DATE.zip"
REMOTE_NAME="your_encrypted_remote"  # Replace with your encrypted Rclone remote name
REMOTE_PATH="path/in/remote/storage"  # Path in your cloud storage where backups will be stored
LOG_FILE="$BACKUP_DIR/backup_$DATE.log"

# Temporary directory for backup structure
TEMP_DIR=$(mktemp -d)

# Logging function
log() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Backup Apache configuration files
CONFIG_DIR="$TEMP_DIR/configuration"
mkdir -p "$CONFIG_DIR"
if cp /etc/apache2/sites-available/*.conf "$CONFIG_DIR"; then
    log "Apache configuration files backed up."
else
    log "ERROR: Failed to backup Apache configuration files."
fi

# Backup MySQL databases
DB_DIR="$TEMP_DIR/databases"
mkdir -p "$DB_DIR"

# Get a list of all databases except system databases
databases=$(mysql -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema|mysql|sys)")

# Dump each database into its own file
for db in $databases; do
    if mysqldump "$db" > "$DB_DIR/$db.sql"; then
        log "Database $db backed up."
    else
        log "ERROR: Failed to back up database $db."
    fi
done

# Backup all folders in /var/www/
WEB_DIR="$TEMP_DIR/websites"
mkdir -p "$WEB_DIR"
if rsync -a --omit-dir-times --ignore-errors /var/www/ "$WEB_DIR"; then
    log "Website files from /var/www/ backed up."
else
    log "ERROR: Failed to back up website files."
fi

# Compress all files into a zip archive
cd "$TEMP_DIR"
if zip -r "$BACKUP_DIR/$BACKUP_FILE" .; then
    log "Backup created at $BACKUP_DIR/$BACKUP_FILE"
else
    log "ERROR: Failed to create backup zip file."
fi

# Delete previous backups from the remote encrypted folder
log "Deleting previous backups from remote..."
if rclone delete "$REMOTE_NAME:$REMOTE_PATH"; then
    log "Previous backups deleted from $REMOTE_NAME at $REMOTE_PATH"
else
    log "ERROR: Failed to delete previous backups from remote storage."
fi

# Upload the backup to cloud storage using the encrypted remote
log "Uploading encrypted backup to cloud storage..."
if rclone copy "$BACKUP_DIR/$BACKUP_FILE" "$REMOTE_NAME:$REMOTE_PATH"; then
    log "Encrypted backup uploaded to $REMOTE_NAME at $REMOTE_PATH"
else
    log "ERROR: Failed to upload encrypted backup to cloud storage."
fi

# Clean up temporary files
rm -rf "$TEMP_DIR"
log "Temporary files cleaned up."

# Optional: Delete old local backups (older than 7 days)
find "$BACKUP_DIR" -type f -name "backup_*.zip" -mtime +7 -exec rm {} \; -exec log "Old local backup deleted: {}" \;

echo "Backup process complete. Log file created at $LOG_FILE."
