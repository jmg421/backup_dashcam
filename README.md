# backup_dashcam.sh

Professional-grade backup and reformat utility for dashcam SD cards.

## Features
- Back up dashcam footage to any rclone-supported remote
- Pre-flight checks (mount point, DCIM folder, remote connectivity)
- Optional remote free space check (requires `jq`)
- Backup verification (`rclone check`)
- Safe unmount and reformat (exFAT or FAT32) on macOS and Linux
- Logging to `backup_dashcam.log`
- Concurrency lock to prevent multiple simultaneous runs
- Dry-run mode and auto-confirmation option

## Requirements
- Bash (>= 4.0)
- `rclone` installed and configured
- `jq` (optional, for remote free space checks)
- On macOS: `diskutil` (built-in)
- On Linux: `findmnt`, `mkfs.exfat` (from `exfat-utils`) for exFAT, `mkfs.vfat` (from `dosfstools`) for FAT32

## Installation
1. Ensure the script has execute permissions:
   ```bash
   chmod +x backup_dashcam.sh
   ```
2. (Optional) Move to a directory in your `$PATH` for easy access:
   ```bash
   mv backup_dashcam.sh /usr/local/bin/
   ```

## Usage
```bash
./backup_dashcam.sh [OPTIONS]
```

### Options
- `-s`, `--source PATH`           Source mount point of the SD card (default: `/Volumes/NO NAME`)
- `-d`, `--dest REMOTE:PATH`      rclone destination (default: `icloud:DashcamBackup`)
- `-f`, `--fs-type TYPE`          Filesystem type: `exFAT` or `FAT32` (default: `exFAT`)
- `-l`, `--label LABEL`           Volume label after formatting (default: `NO NAME`)
- `-n`, `--dry-run`               Perform a trial run without making any changes
- `-y`, `--yes`                   Skip all confirmation prompts
- `-v`, `--verbose`               Enable verbose output
- `-h`, `--help`                  Show help and exit

### Examples
- Default backup and format:
  ```bash
  ./backup_dashcam.sh
  ```
- Dry run (no changes):
  ```bash
  ./backup_dashcam.sh --dry-run
  ```
- Custom source and destination:
  ```bash
  ./backup_dashcam.sh -s /media/dashcam -d gdrive:MyDashcam
  ```

## Logging
All output is appended to `backup_dashcam.log` in the script's directory.

## License
MIT License (or your preferred license)