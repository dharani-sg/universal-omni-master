#!/bin/sh
# /etc/apk/commit_hooks.d/00-omni-snapshot
# apk has no pre-transaction hook — this runs after commit.
/usr/bin/omni-snapshot create pretxn apk-post || true
