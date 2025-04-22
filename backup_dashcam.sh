#!/usr/bin/env bash
#
# backup_dashcam.sh - Professional-grade backup and reformat utility for dashcam SD cards.
#
# Usage: backup_dashcam.sh [OPTIONS]
#
# Options:
#   -s, --source PATH           Source mount point of the SD card (default: /Volumes/NO NAME)
#   -d, --dest REMOTE:PATH      rclone destination remote:path (default: icloud:DashcamBackup)
#   -f, --fs-type TYPE          Filesystem type for formatting: exFAT or FAT32 (default: exFAT)
#   -l, --label LABEL           Volume label to set after formatting (default: NO NAME)
#   -n, --dry-run               Perform a trial run without making any changes
#   -y, --yes                   Skip all confirmation prompts
#   -v, --verbose               Enable verbose output
#   -h, --help                  Show this help message and exit
#
# Environment variables:
#   SOURCE, DEST_REMOTE, FS_TYPE, LABEL, LOGFILE can be set to override defaults.
#
set -euo pipefail

# Default configuration
SOURCE="${SOURCE:-/Volumes/NO NAME}"
DEST_REMOTE="${DEST_REMOTE:-icloud:DashcamBackup}"
FS_TYPE="${FS_TYPE:-exFAT}"
LABEL="${LABEL:-NO NAME}"
DRY_RUN=false
FORCE=false
VERBOSE=false

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${LOGFILE:-$SCRIPT_DIR/backup_dashcam.log}"
LOCKFILE="/tmp/${SCRIPT_NAME}.lock"

# Print usage information
usage() {
    grep '^#' "$0" | sed 's/^#//'
}

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Error handler
error_handler() {
    local exit_code=$?
    log "❌  Error on line $1 (exit code: $exit_code)"
    exit $exit_code
}

# Interrupt handler
interrupt_handler() {
    log "❌  Interrupted by user."
    exit 1
}

# Parse command-line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--source) SOURCE="$2"; shift 2;;
        -d|--dest) DEST_REMOTE="$2"; shift 2;;
        -f|--fs-type) FS_TYPE="$2"; shift 2;;
        -l|--label) LABEL="$2"; shift 2;;
        -n|--dry-run) DRY_RUN=true; shift;;
        -y|--yes) FORCE=true; shift;;
        -v|--verbose) VERBOSE=true; shift;;
        -h|--help) usage; exit 0;;
        *) echo "Unknown option: $1" >&2; usage; exit 1;;
    esac
done

# Prepare logging
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

# Set traps
trap 'error_handler $LINENO' ERR
trap 'interrupt_handler' SIGINT SIGTERM

# Prevent concurrent runs
if ! ( set -o noclobber; >"$LOCKFILE" ); then
    log "❌  Another instance of $SCRIPT_NAME is running. Exiting."
    exit 1
fi
trap 'rm -f "$LOCKFILE"' EXIT

# Start of script
log "🔄  Starting backup"
log "Configuration: SOURCE=$SOURCE | DEST_REMOTE=$DEST_REMOTE | FS_TYPE=$FS_TYPE | LABEL=$LABEL | DRY_RUN=$DRY_RUN | VERBOSE=$VERBOSE"

# Pre-flight checks
command -v rclone >/dev/null 2>&1 || { log "Error: rclone not found. Please install rclone."; exit 1; }

if [[ ! -d "$SOURCE" ]]; then
    log "Error: source directory '$SOURCE' does not exist."
    exit 1
fi

# Check for DCIM folder to prevent wiping wrong drive
if [[ ! -d "$SOURCE/DCIM" ]]; then
    log "Warning: No DCIM directory found in '$SOURCE'."
    if [[ "$FORCE" != true ]]; then
        read -r -p "Continue anyway? [y/N]: " ans
        [[ "$ans" =~ ^[Yy] ]] || { log "Aborted by user."; exit 1; }
    fi
fi

# Verify remote connectivity
if ! rclone ls "${DEST_REMOTE%/}" --max-duration 30s >/dev/null 2>&1; then
    log "Error: cannot reach remote '$DEST_REMOTE'."
    exit 1
fi

# Optional: check remote free space (requires jq)
if command -v jq >/dev/null 2>&1; then
    if avail_bytes=$(rclone about "${DEST_REMOTE%/}" --json 2>/dev/null | jq -r '.free // empty'); then
        avail_kb=$(( avail_bytes / 1024 ))
        req_kb=$(du -sk "$SOURCE" | awk '{print $1}')
        log "Remote free space: ${avail_kb}K | Required: ${req_kb}K"
        if (( req_kb > avail_kb )); then
            log "Error: not enough space on remote."
            exit 1
        fi
    else
        log "Warning: Failed to retrieve free space info. Skipping space check."
    fi
else
    log "Warning: jq not installed. Skipping remote free space check."
fi

# Perform backup (copy)
log "🔄  Running rclone copy..."
if [[ "$DRY_RUN" == true ]]; then
    rclone copy "$SOURCE" "$DEST_REMOTE" --dry-run --verbose
    log "Dry run complete. Exiting."
    exit 0
else
    RCLONE_OPTS=( --progress --stats=1m )
    $VERBOSE && RCLONE_OPTS+=( --verbose )
    rclone copy "$SOURCE" "$DEST_REMOTE" "${RCLONE_OPTS[@]}"
fi
log "✅  rclone copy completed"

# Verify backup integrity
log "🔍  Verifying backup..."
CHECK_OPTS=( check "$SOURCE" "$DEST_REMOTE" --one-way --size-only )
$VERBOSE && CHECK_OPTS+=( --verbose )
rclone "${CHECK_OPTS[@]}"
log "✅  Backup verification succeeded"

# Confirmation before formatting
if [[ "$FORCE" != true ]]; then
    read -r -p "🔧  Unmount and format the card now? This will erase all data. Continue? [y/N]: " ans
    [[ "$ans" =~ ^[Yy] ]] || { log "Aborted by user."; exit 1; }
fi

# Unmount and format
OS="$(uname)"
if [[ "$OS" == "Darwin" ]]; then
    dev_node=$(diskutil info "$SOURCE" | awk -F': ' '/Device Node/ {print $2}')
    [[ -n "$dev_node" ]] || { log "Error: cannot find device node."; exit 1; }
    log "🔄  Unmounting disk $dev_node"
    diskutil unmountDisk "$dev_node"
    log "🗑  Erasing disk as $FS_TYPE with label '$LABEL'"
    diskutil eraseDisk "$FS_TYPE" "$LABEL" "$dev_node"
elif [[ "$OS" == "Linux" ]]; then
    device=$(findmnt -nr -o SOURCE "$SOURCE")
    [[ -n "$device" ]] || { log "Error: cannot find device for '$SOURCE'."; exit 1; }
    log "🔄  Unmounting $SOURCE"
    umount "$SOURCE"
    if [[ "$FS_TYPE" == "exFAT" ]]; then
        command -v mkfs.exfat >/dev/null 2>&1 || { log "Error: mkfs.exfat not found."; exit 1; }
        log "🗑  Formatting $device as exFAT with label '$LABEL'"
        mkfs.exfat -n "$LABEL" "$device"
    elif [[ "$FS_TYPE" == "FAT32" ]]; then
        command -v mkfs.vfat >/dev/null 2>&1 || { log "Error: mkfs.vfat not found."; exit 1; }
        log "🗑  Formatting $device as FAT32 with label '$LABEL'"
        mkfs.vfat -F 32 -n "$LABEL" "$device"
    else
        log "Error: unsupported FS_TYPE '$FS_TYPE'"
        exit 1
    fi
else
    log "Error: unsupported OS '$OS'"
    exit 1
fi

log "✅  Card reformatted successfully (FS: $FS_TYPE, Label: '$LABEL')"
exit 0