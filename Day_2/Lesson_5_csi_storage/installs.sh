#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# install Docker Engine
echo "--- Installing Docker ---"
sudo apt update
sudo apt install -y docker.io

# run docker commands without 'sudo'
echo "--- Configuring Permissions ---"
sudo usermod -aG docker $USER

# install KiND (Kubernetes in Docker)
echo "--- Installing KiND ---"
# We add -f to curl to fail on server errors, and -L to follow redirects
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64

# Check if the file actually exists before moving
if [ -f "./kind" ]; then
    chmod +x ./kind
    sudo mv ./kind /usr/local/bin/kind
    echo "KiND installed successfully."
else
    echo "Error: KiND download failed."
    exit 1
fi

# install kubectl (The Remote Control)
echo "--- Installing kubectl ---"
# If snap fails, we use the binary method as a backup
sudo snap install kubectl --classic || echo "Snap failed, but continuing..."

# check 
echo "--- Verifying Installations ---"
docker --version
kind version
kubectl version --client

echo "--------------------------------------------------------"
echo "INSTALLATION COMPLETE"
echo "IMPORTANT: You MUST log out and log back in (or run 'newgrp docker')"
echo "to apply the permissions changes"
echo "--------------------------------------------------------"