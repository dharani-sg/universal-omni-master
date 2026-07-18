# Git Sync and Recovery Guide

## Overview

GitHub is the canonical transport for UOM code. Both laptop and phone sync through GitHub, not directly to each other.

## Sync Architecture

```
Laptop ──push/fetch──► GitHub ◄──fetch── Phone
```

## Daily Sync

### From Laptop

```sh
# Check status
bin/uom-sync status

# Pull latest
bin/uom-sync pull

# Push changes
bin/uom-sync push
```

### From Phone

```sh
cd ~/src/universal-omni-master
git fetch origin
git pull --ff-only origin refactor/structure-audit-2026-07-17
```

## Conflict Resolution

If `git pull --ff-only` fails:

1. **STOP** — do not auto-resolve
2. Check `git log --oneline -5` on both sides
3. Determine which changes are newer
4. Manually merge or cherry-pick
5. Test before pushing

## Branch Policy

| Branch | Purpose | Protected |
|--------|---------|-----------|
| `refactor/structure-audit-2026-07-17` | Active development | No force-push |
| `main` | Stable releases | No force-push |

## Recovery Scenarios

### Phone Behind GitHub

```sh
cd ~/src/universal-omni-master
git fetch origin
git pull --ff-only origin refactor/structure-audit-2026-07-17
```

### Phone Ahead of GitHub (rare)

```sh
git push origin refactor/structure-audit-2026-07-17
```

### Phone on Wrong Branch

```sh
git stash push -m "stale-$(date +%Y%m%d)"
git checkout refactor/structure-audit-2026-07-17
git pull --ff-only origin refactor/structure-audit-2026-07-17
```

### Phone Has Uncommitted Changes

```sh
git stash push -m "local-changes-$(date +%Y%m%d)"
git pull --ff-only origin refactor/structure-audit-2026-07-17
# Apply stash if needed
git stash pop
```

## Phone GitHub Write Access

To enable phone push to GitHub:

1. Generate SSH key on guest:
   ```sh
   ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github -N ""
   ```

2. Show public key:
   ```sh
   cat ~/.ssh/id_ed25519_github.pub
   ```

3. Add as GitHub deploy key (write access):
   - Go to repo Settings → Deploy keys → Add key
   - Paste public key
   - Check "Allow write access"

4. Configure SSH:
   ```sh
   cat >> ~/.ssh/config << EOF
   Host github.com
       IdentityFile ~/.ssh/id_ed25519_github
       IdentitiesOnly yes
   EOF
   ```

5. Test:
   ```sh
   ssh -T git@github.com
   ```

## Backup Strategy

| What | Where | Frequency |
|------|-------|-----------|
| Code | GitHub | Every commit |
| VM disk | External storage | Weekly |
| SSH keys | Encrypted backup | Once |
| Phone state | GitHub (via git) | Every commit |
