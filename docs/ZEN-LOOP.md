# Zen Loop Cloud Code Pipeline

Reference: HEAD f34b633, tag v0.31.0-2026-07-17. Date: 2026-07-17.

## Overview

The Zen Loop is a cloud-only code generation pipeline that replaces local LLM
inference with pure cloud models. No ollama, no sudo, no local inference binaries.
Every request goes through `opencode --model opencode/deepseek-v4-flash-free`
via stdin pipe.

## Architecture

```
queue.json (pending)
    |
    v
uom-generator.sh  (reads pending tasks, calls opencode via stdin)
    |
    | writes to .uom-agent/generated/<task_id>.sh
    | creates .uom-agent/generated/<task_id>.ready marker
    v
uom-verifier.sh  (watches for .ready markers)
    |
    | runs: sh -n, policy check, optional dry-run
    | writes result to .uom-agent/verified/<task_id>.result
    | moves .ready to .done
    v
queue.json (verified/failed)
```

## Scripts

| Script | Purpose | Location |
|--------|---------|----------|
| uom-reconcile.sh | 6-step orchestrator (preflight + tmux + boot + tunnel + guardian + zen) | scripts/uom-reconcile.sh |
| uom-generator.sh | Cloud code generator via opencode stdin with retry + fallback | scripts/uom-generator.sh |
| uom-verifier.sh | Syntax/policy verifier (no LLM calls) | scripts/uom-verifier.sh |

## Singleton Protection

Both generator and verifier use PID-file-based singleton guards:

- `gen.lock` / `gen.pid` in `.uom-agent/runtime/`
- `ver.lock` / `ver.pid` in `.uom-agent/runtime/`

Each checks for an existing process via `kill -0` before starting. Stale locks
from crashed processes are recycled.

## Generator Behavior

- Polls `queue.json` for `pending` tasks every 5 seconds
- Calls `opencode --model opencode/deepseek-v4-flash-free` via stdin pipe
- 3 retries with 10s backoff on failure
- Stub generation fallback when cloud API is unreachable
- Atomic output: writes to temp file, renames after successful generation
- Writes `.ready` marker with metadata (task ID, timestamp, model, line count)
- Idempotent: skips already-generated tasks

## Verifier Behavior

- Watches `.uom-agent/generated/*.ready` files
- Runs checks:
  1. Syntax: `sh -n` for .sh files, `python3 -m py_compile` for .py files
  2. Policy: no curl-pipe-shell, no sudo/doas, no deprecated port 18022,
     no unsafe /tmp writes, checks shebang and `set -u`
  3. Optional dry-run: runs `scripts/uom-dryrun.sh` on first verification
- Writes structured JSON result to `.uom-agent/verified/<task_id>.result`
- Updates queue.json: `verified` or `failed`
- Provides feedback for generator on failures

## Verifier Failure Prevention

- Verifier failure blocks activation of generated output
- Generated output only becomes active when result is PASS or WARN
- Failed tasks remain in queue as `failed` for manual review
- Empty output from generator is caught and rejected

## Usage

```sh
# Full pipeline:
sh scripts/uom-reconcile.sh

# Just generate:
scripts/uom-generator.sh "write a POSIX sh function to check disk health"

# Just verify:
scripts/uom-verifier.sh path/to/file.sh
```

## Cloud Model Policy

- Model: `opencode/deepseek-v4-flash-free` (free tier)
- No API key required
- No authentication-dependent provider
- No local LLM (Ollama removed in M30.5)
- No sudo-based inference path
