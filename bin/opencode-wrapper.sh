#!/data/data/com.termux/files/usr/bin/sh
# opencode wrapper - runs via proot Alpine with musl binary
exec proot-distro login alpine -- sh -c "
  export HOME=/root
  export PATH=/usr/local/bin:/usr/bin:/bin
  cd \"\$(pwd)\"
  /usr/local/bin/opencode \$*\"
" 2>/dev/null
