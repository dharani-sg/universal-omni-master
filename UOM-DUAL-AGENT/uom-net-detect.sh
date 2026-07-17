#!/bin/sh
# tools/uom-net-detect.sh — Detect network mode for orchestrator
# Returns: hotspot | external | offline
# Outputs shell-eval-safe KEY=VALUE lines

_gw=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
_my_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/{print $7; exit}')

if [ -z "$_gw" ] || [ -z "$_my_ip" ]; then
    printf 'NET_MODE=offline\n'; exit 0
fi

if [ "$_gw" = "192.168.43.1" ]; then
    printf 'NET_MODE=hotspot\nPHONE_IP=192.168.43.1\nLAPTOP_IP=%s\n' "$_my_ip"
else
    printf 'NET_MODE=external\nLAPTOP_IP=%s\nGATEWAY=%s\n' "$_my_ip" "$_gw"
fi
