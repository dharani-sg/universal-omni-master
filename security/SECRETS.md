# UOM Secrets Management (v0.29.0)

## Storage Pattern

All API keys and secrets go in `~/.config/uom/secrets.env` (mode 600, NOT in git):

```
~/.config/uom/secrets.env  (600 — outside repo, NEVER committed)
install/secrets.env.template  (644 — committed, keys blank)
```

## How Scripts Load Secrets

```sh
. "${HOME}/.config/uom/secrets.env" 2>/dev/null || {
    echo "[UOM] No secrets file at ~/.config/uom/secrets.env"
    echo "[UOM] Create from template: cp install/secrets.env.template ~/.config/uom/secrets.env"
    exit 1
}
```

## Setup

```sh
cp src/universal-omni-master/install/secrets.env.template ~/.config/uom/secrets.env
chmod 600 ~/.config/uom/secrets.env
# Edit ~/.config/uom/secrets.env and fill in values
```

## Pre-Commit Guard

A pre-commit hook scans staged files for secret patterns (API keys, SSH private keys).
If detected, the commit is **blocked**. Install with:

```sh
sh security/install-hooks.sh
```

## What Gets Blocked

- `sk-ant-` (Anthropic API key prefix)
- `ANTHROPIC_API_KEY=` or `OPENAI_API_KEY=`
- `ssh-rsa AAAA` (public keys — shouldn't be in code)
- `BEGIN PRIVATE KEY` or `BEGIN OPENSSH PRIVATE KEY` (actual private keys)

## Rule of Thumb

If it's a secret, it goes in `~/.config/uom/secrets.env`, not in any tracked file.

<!-- last-sync: 2026-07-17T07:35:34Z -->
