#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y \
  golang-cfssl \
  docker.io \
  kubectx \
  openjdk-17-jre-headless \
  ca-certificates curl gnupg lsb-release

sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker "$USER"

echo "==> Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
rm kubectl

echo "==> Installing kind v0.24.0..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

echo "==> Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
sudo ./get_helm.sh
rm get_helm.sh

echo "Done. Log out and back in (or run 'newgrp docker') so the docker group takes effect."
