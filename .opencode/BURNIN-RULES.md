# Burn-in Pre-Authorization Rules — dual-agent-20260718

## Duration
- UOM_BURNIN_HOURS=8
- Start: 2026-07-19 ~20:00 UTC
- End: 2026-07-20 ~04:00 UTC

## Allowlist (files that MAY be modified during burn-in)
- .uom-agent/runtime/*
- .uom-agent/logs/*
- .uom-agent/generated/*
- .uom-agent/verified/*
- .uom-agent/feedback/*
- .uom-agent/queue.json
- .uom-agent/done.json
- .uom-agent/state.json
- .uom-agent/phone.ip
- .uom-agent/laptop.ip
- .uom-agent/phone.host
- .uom-agent/laptop.host

## Deny (files that MUST NOT be modified)
- scripts/*.sh
- tools/*.sh
- orchestrators/*.sh
- bin/*.sh
- tests/*.sh
- .uom-agent/context/*
- .uom-agent/queue.json.schema (if exists)
- .uom-agent/state.json.schema (if exists)
- docs/*.md
- *.json (project root)
- *.md (project root)

## Rules
1. No edits to stable/refactor branch — review/fix only in burn-in branch
2. No new feature scripts — only runtime data and logs
3. Generator writes to generated/, verifier writes to verified/
4. If a bug is found in a script, log it, do NOT edit the script during burn-in
5. On failure: queue mutation (reset/fail) is allowed, script edits are NOT

## Monitoring
- Status: `sh bin/uom-status.sh`
- Generator log: `.uom-agent/logs/generator.log`
- Verifier log: `.uom-agent/logs/verifier.log`
- Reconcile log: `.uom-agent/logs/reconcile.log`
