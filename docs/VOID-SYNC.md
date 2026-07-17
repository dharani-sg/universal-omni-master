# Void Linux Dual-Boot Sync

This machine dual-boots Alpine Linux (sda4, primary) and Void Linux (sda3, glibc/runit).

## After booting Void

```sh
cd ~/src/universal-omni-master
git pull                    # Brings in latest commits + tags
git tag --list 'v*' | sort -V  # Verify tags present
sh scripts/uom-reconcile.sh   # 6-step: preflight -> tmux -> boot -> tunnel -> guardian -> zen
```

## Runit services (optional)

Create runit service for the port-guardian on Void:

```sh
sudo ln -s ~/src/universal-omni-master/init/runit/port-guardian /etc/runit/sv/
sudo ln -s /etc/runit/sv/port-guardian /var/service/
```

(Service files not yet created — pending M30.5.)
