#!/data/data/com.termux/files/usr/bin/sh
set -e
BASE=http://192.168.40.90:8765
curl -fsSL "$BASE/b.sh" -o "$HOME/b.sh"
chmod +x "$HOME/b.sh"
sh "$HOME/b.sh"
mkdir -p "$HOME/src/universal-omni-master/tools"
cd "$HOME/src/universal-omni-master/tools"
curl -fsSL "$BASE/t.tgz" | tar -xz
chmod +x *.sh
echo "OK bootstrap done. Next: sh ~/bin/uom-reverse-ssh.sh"
