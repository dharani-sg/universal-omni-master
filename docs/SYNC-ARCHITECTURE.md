# Git Sync Architecture

## Overview

GitHub is the canonical transport. Laptop and phone both use GitHub (not each other) as the source of truth.

```
┌─────────┐     push/fetch     ┌─────────┐     fetch     ┌─────────┐
│  Laptop  │ ◄──────────────► │ GitHub  │ ◄──────────── │  Phone  │
│ (laptop) │                   │  (repo) │               │ (guest) │
└─────────┘                    └─────────┘               └─────────┘
```

## Branch Policy

- **Canonical branch:** `refactor/structure-audit-2026-07-17`
- Both laptop and phone track this branch
- No merge conflicts — fast-forward only
- Phone queue.json: runtime state, not committed (local diff OK)

## Sync Tools

| Command | Description |
|---------|-------------|
| `bin/uom-sync status` | Show local/remote/GitHub SHA |
| `bin/uom-sync fetch` | Fetch from origin |
| `bin/uom-sync pull` | Fetch + fast-forward only |
| `bin/uom-sync push` | Push to origin (requires clean tree) |
| `bin/uom-sync verify` | Check local == GitHub SHA |
| `bin/uom-sync-status` | Quick status (no lock) |

## Rules

1. GitHub becomes canonical transport after initial sync
2. Laptop NOT required for phone operation (post-sync)
3. Pull = fetch + ff-only (never merge over dirty tree)
4. Push requires clean tested tree
5. No auto-conflict resolution (STOP with GIT_SYNC_CONFLICT_REQUIRES_REVIEW)
6. Singleton lock prevents concurrent sync operations
7. Both machines use GitHub (not each other) after initial sync

## Recovery

- **Laptop loss:** Phone has full repo via GitHub
- **Phone loss:** Laptop has full repo locally + GitHub
- **GitHub loss:** Both laptop and phone have local copies
- **New laptop:** Clone from GitHub, verify SHA matches phone

## Phone GitHub Write Identity

- Never copy laptop private key
- Generate dedicated repo-specific SSH key on guest
- Add as GitHub deploy key (write access) or use interactive login
- Until authorized: GIT_WRITE_AUTH_REQUIRED (read-only fetch OK if public)

## Known Issues

- Phone queue.json has stale runtime changes (stash on branch switch)
- Phone stash list has 8 entries (historical, can be cleaned)
- Guest has no .git (extracted tree, accessed via phone SSH)
