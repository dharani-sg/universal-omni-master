#!/bin/sh
# /usr/local/bin/xbps-install (wrapper)
# Install step: mv /usr/bin/xbps-install /usr/bin/xbps-install.real
# then cp this file to /usr/local/bin/xbps-install && chmod +x
# /usr/local/bin takes precedence over /usr/bin in Void's default PATH.
_real="/usr/bin/xbps-install.real"
if [ ! -x "$_real" ]; then
    printf 'xbps-wrapper: real xbps-install not found at %s\n' "$_real" >&2
    exec /usr/bin/xbps-install "$@"    # fall through to real binary
fi
/usr/bin/omni-snapshot create pretxn xbps || true
exec "$_real" "$@"
