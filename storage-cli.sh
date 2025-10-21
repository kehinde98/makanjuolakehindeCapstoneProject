#!/usr/bin/env bash
set -euo pipefail

# === CONFIG ===
RESOURCE_GROUP="${RESOURCE_GROUP:-rgKehindeCloudProj}"
LOCATION="${LOCATION:-eastus}"
STORAGE_ACCOUNT_NAME="${STORAGE_ACCOUNT_NAME:-kehindestorageacct$((RANDOM%99999))}"
CONTAINER_NAME="${CONTAINER_NAME:-myblobcontainer}"
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/blob_storage.log"
ENV_FILE=".blob_storage_env"

mkdir -p "$LOG_DIR"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"; }

# === LOAD ENVIRONMENT IF EXISTS ===
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# === INITIALIZE STORAGE ACCOUNT (IDEMPOTENT) ===
init_storage() {
    log "Initializing Azure Blob Storage..."

    # Create resource group if it doesn't exist
    if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
        log "Creating resource group $RESOURCE_GROUP..."
        az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    fi

    # Create storage account if it doesn't exist
    if ! az storage account show --name "$STORAGE_ACCOUNT_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
        log "Creating storage account $STORAGE_ACCOUNT_NAME..."
        az storage account create \
            --name "$STORAGE_ACCOUNT_NAME" \
            --resource-group "$RESOURCE_GROUP" \
            --location "$LOCATION" \
            --sku Standard_LRS \
            --kind StorageV2 \
            --output none
    fi

    # Enable public blob access
    az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --allow-blob-public-access true \
        --output none

    # Get storage key
    STORAGE_KEY=$(az storage account keys list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query '[0].value' -o tsv)

    # Create container if it doesn't exist
    if ! az storage container show --name "$CONTAINER_NAME" --account-name "$STORAGE_ACCOUNT_NAME" --account-key "$STORAGE_KEY" &>/dev/null; then
        log "Creating container $CONTAINER_NAME..."
        az storage container create \
            --name "$CONTAINER_NAME" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --account-key "$STORAGE_KEY" \
            --public-access blob \
            --output none
    fi

    # Save environment for future runs
    cat > "$ENV_FILE" <<EOF
STORAGE_ACCOUNT_NAME="$STORAGE_ACCOUNT_NAME"
STORAGE_KEY="$STORAGE_KEY"
CONTAINER_NAME="$CONTAINER_NAME"
RESOURCE_GROUP="$RESOURCE_GROUP"
LOCATION="$LOCATION"
EOF

    log "Azure Blob Storage initialized successfully."
}

# === STORAGE OPERATIONS ===
upload_file() {
    local file_path="$1"
    log "Uploading $file_path..."
    az storage blob upload \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER_NAME" \
        --name "$(basename "$file_path")" \
        --overwrite true \
        --file "$file_path" \
        --output table
}

download_file() {
    local blob_name="$1"
    local dest_path="${2:-$blob_name}"
    log "Downloading $blob_name to $dest_path..."
    az storage blob download \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER_NAME" \
        --name "$blob_name" \
        --file "$dest_path" \
        --output table
}

list_files() {
    log "Listing blobs in $CONTAINER_NAME..."
    az storage blob list \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER_NAME" \
        --output table
}

delete_file() {
    local blob_name="$1"
    log "Deleting blob $blob_name..."
    az storage blob delete \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --account-key "$STORAGE_KEY" \
        --container-name "$CONTAINER_NAME" \
        --name "$blob_name" \
        --output table
}

# === SCRIPT START ===
# Initialize storage silently if STORAGE_KEY is missing
if [ -z "${STORAGE_KEY:-}" ]; then
    init_storage
fi

# If no arguments, do nothing (storage already initialized)
if [ $# -lt 1 ]; then
    exit 0
fi

# === COMMAND DISPATCH ===
COMMAND="$1"; shift
case "$COMMAND" in
    init) init_storage ;;
    upload) upload_file "$@" ;;
    download) download_file "$@" ;;
    list) list_files ;;
    delete) delete_file "$@" ;;
    *) exit 0 ;;  # silently ignore unknown commands
esac
