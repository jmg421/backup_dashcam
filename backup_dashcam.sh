#!/usr/bin/env bash
set -euo pipefail

#
# backup_dashcam.sh
#   1) rclone-copy from /Volumes/NO NAME to your iCloud remote
#   2) if successful, unmount & reformat the SD card
#

### Configuration (customize) ###
SOURCE="/Volumes/NO NAME"
DEST_REMOTE="icloud:DashcamBackup"   # your rclone remote:path
FS_TYPE="exFAT"                     # "exFAT" or "FAT32"
LABEL="NO NAME"                     # volume label to set after formatting
##############################

# Ensure rclone is installed
command -v rclone >/dev/null 2>&1 || { echo "Error: rclone not found. Install rclone first." >&2; exit 1; }

echo "🔄  Starting backup of '$SOURCE' → '$DEST_REMOTE'..."
rclone copy "$SOURCE" "$DEST_REMOTE" --progress --stats=1m
echo "✅  Backup completed."

echo "🔧  Proceeding to unmount & reformat the card..."

OS="$(uname)"
if [ "$OS" = "Darwin" ]; then
        # macOS: find the device node for the mountpoint
        DEV_NODE="$(diskutil info "$SOURCE" | awk -F': ' '/Device Node/ {print $2}')"
        [ -n "$DEV_NODE" ] || { echo "Error: cannot find device node for $SOURCE" >&2; exit 1; }

       diskutil unmountDisk "$DEV_NODE"
        diskutil eraseDisk "$FS_TYPE" "$LABEL" "$DEV_NODE"

elif [ "$OS" = "Linux" ]; then
        # Linux: find the source device, unmount & mkfs
        DEVICE="$(findmnt -nr -o SOURCE "$SOURCE")"
        [ -n "$DEVICE" ] || { echo "Error: cannot find device for $SOURCE" >&2; exit 1; }

       umount "$SOURCE"

       if [ "$FS_TYPE" = "exFAT" ]; then
        command -v mkfs.exfat >/dev/null 2>&1 || { echo "Error: mkfs.exfat not found. Install exfat-utils." >&2; exit 1; }
        mkfs.exfat -n "$LABEL" "$DEVICE"
        elif [ "$FS_TYPE" = "FAT32" ]; then
        command -v mkfs.vfat >/dev/null 2>&1 || { echo "Error: mkfs.vfat not found. Install dosfstools." >&2; exit 1; }
        mkfs.vfat -F 32 -n "$LABEL" "$DEVICE"
        else
        echo "Error: unsupported FS_TYPE='$FS_TYPE'" >&2
        exit 1
        fi

else
        echo "Error: unsupported OS: $OS" >&2
        exit 1
fi

echo "✅  Card reformatted ($FS_TYPE, label='$LABEL')."
exit 0
