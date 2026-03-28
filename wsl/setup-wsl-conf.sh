#!/usr/bin/env bash
set -euo pipefail

if [ -e /etc/wsl.conf ]; then
    echo "Current /etc/wsl.conf contents:"
    cat /etc/wsl.conf
    echo "already configured"
    exit 0
fi

sudo tee /etc/wsl.conf > /dev/null <<'EOF'
[interop]
enabled=true
appendWindowsPath=true

[systemd]
enabled=true

[automount]
enabled=true
root=/mnt
options=metadata,uid=1000,gid=1000
EOF

if [ ! -f /etc/wsl.conf ]; then
    echo "Failed to create /etc/wsl.conf" >&2
    exit 1
fi

echo "Reminder: Restart WSL with 'wsl --shutdown' for changes to take effect."
exit 0
