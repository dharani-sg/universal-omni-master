#!/bin/sh
# antigravity — CLI easter egg for Alpine VM
# Inspired by XKCD 353 ("Python")
# POSIX sh. Idempotent. No dependencies beyond what's in base Alpine.

ANTIGRAVITY_DIR="${HOME}/.antigravity"
ANTIGRAVITY_CACHE="${ANTIGRAVITY_DIR}/xkcd-353.txt"
ANTIGRAVITY_URL="https://xkcd.com/353/"

mkdir -p "${ANTIGRAVITY_DIR}" 2>/dev/null

cat << "EOF"
                 _
                (_)
        |\\      _       ___
        | \\    / \\     |   \\
        |  \\  /   \\    |    \\
        |   \\/     \\   |     \\
        |          /   |     /
        |         /    |    /
        |________/     |___/

    "Python" — XKCD #353

EOF

if [ -f "${ANTIGRAVITY_CACHE}" ]; then
    cat "${ANTIGRAVITY_CACHE}"
else
    echo "  Fetching comic transcript..."
    if command -v wget >/dev/null 2>&1; then
        wget -q -O - "${ANTIGRAVITY_URL}" 2>/dev/null | \
            sed -n 's/.*<div id="comic">.*<img.*alt="\([^"]*\)".*/\1/p' \
            > "${ANTIGRAVITY_CACHE}" 2>/dev/null && \
            cat "${ANTIGRAVITY_CACHE}" 2>/dev/null || \
            echo "  (could not fetch — no network?)"
    elif command -v curl >/dev/null 2>&1; then
        curl -s "${ANTIGRAVITY_URL}" 2>/dev/null | \
            sed -n 's/.*<div id="comic">.*<img.*alt="\([^"]*\)".*/\1/p' \
            > "${ANTIGRAVITY_CACHE}" 2>/dev/null && \
            cat "${ANTIGRAVITY_CACHE}" 2>/dev/null || \
            echo "  (could not fetch — no network?)"
    else
        echo "  Every time you fly off you're having an adventure!"
        echo "  (install wget or curl for live fetch)"
    fi
fi

cat << "EOF"

  import antigravity
  # (well, that was anticlimactic)

EOF
