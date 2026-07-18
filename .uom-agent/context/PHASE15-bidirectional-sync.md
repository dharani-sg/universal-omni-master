Task M35: Bidirectional Sync
Create a sync wrapper script that:
1. Detects if running on phone or laptop
2. Uses rsync over SSH to sync .uom-agent directories
3. Phone pushes generated/ to laptop
4. Laptop pushes verified/ to phone
5. Runs every 30 seconds in a loop

Script: tools/uom-sync-loop.sh
Requirements: POSIX sh, set -u, rsync, SSH
