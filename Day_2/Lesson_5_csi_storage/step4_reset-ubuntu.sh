#!/bin/bash

# Do not exit on error
set +e

echo "--- 1. Tearing down Kubernetes (KiND) ---"
if command -v kind &> /dev/null; then
    kind delete clusters --all || true
    sudo rm -f /usr/local/bin/kind
    echo "KiND clusters and binary removed."
fi

echo "--- 2. Cleaning up kubectl ---"
if command -v kubectl &> /dev/null; then
    sudo snap remove kubectl || true
    sudo rm -f /usr/local/bin/kubectl || true
    rm -rf ~/.kube
    echo "kubectl removed and config cleared."
fi

echo "--- 3. Wiping Docker Environment & Systemd States ---"
if command -v docker &> /dev/null || [ -d /var/lib/docker ]; then
    echo "Stopping all containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    
    echo "Resetting systemd units (Fixes Socket Activation errors)..."
    sudo systemctl stop docker.service docker.socket 2>/dev/null || true
    sudo systemctl unmask docker.service docker.socket 2>/dev/null || true
    
    echo "Uninstalling Docker packages..."
    sudo apt purge -y docker.io docker-doc docker-compose podman-docker containerd runc || true
    sudo apt autoremove -y || true
    
    # Clean up leftovers that apt purge might miss
    sudo rm -rf /var/lib/docker
    sudo rm -rf /etc/docker
    sudo rm -f /var/run/docker.sock
    echo "Docker wiped and systemd units unmasked."
fi

echo "--- 4. Removing Longhorn & Storage Dependencies ---"
sudo systemctl stop iscsid || true
sudo apt purge -y open-iscsi nfs-common || true
sudo apt autoremove -y || true
sudo rm -rf /var/lib/longhorn
echo "Storage dependencies removed."

echo "--- 5. Final Filesystem Cleanup ---"
# We keep the step scripts so you don't have to recreate them!
rm -f kind-config.yaml
sudo apt clean
echo "Configuration files and cache cleared."

echo "--------------------------------------------------------"
echo "RESETS COMPLETE"
echo "--------------------------------------------------------"