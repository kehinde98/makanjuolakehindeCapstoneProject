#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
APP_FILE="hello.txt"   # Change to any file you want to upload
DOWNLOAD_NAME="downloaded_${APP_FILE}"
LOG_FILE="./logs/deploy.log"

mkdir -p "$(dirname "$LOG_FILE")"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"; }

log "🚀 Starting full Azure Blob Storage deployment..."

# === STEP 1: Initialize storage account ===
log "Step 1: Initializing Azure Storage account and container..."
./storage-cli.sh init

# === STEP 2: Upload file ===
if [ -f "$APP_FILE" ]; then
    log "Step 2: Uploading file ($APP_FILE)..."
    ./storage-cli.sh upload "$APP_FILE"
else
    log "⚠️ File '$APP_FILE' not found. Creating a sample file..."
    echo "This is a sample file uploaded at $(date)" > "$APP_FILE"
    ./storage-cli.sh upload "$APP_FILE"
fi

# === STEP 3: List files in the container ===
log "Step 3: Listing files..."
./storage-cli.sh list

# === STEP 4: Download the uploaded file ===
log "Step 4: Downloading uploaded file as '$DOWNLOAD_NAME'..."
./storage-cli.sh download "$(basename "$APP_FILE")" "$DOWNLOAD_NAME"

# === STEP 5: Delete the uploaded file from Azure ===
log "Step 5: Deleting blob $(basename "$APP_FILE")..."
./storage-cli.sh delete "$(basename "$APP_FILE")"

# === STEP 6: Final listing ===
log "Step 6: Final list to confirm deletion..."
./storage-cli.sh list

log "✅ Deployment completed successfully!"
