#!/usr/bin/env bash
# Installs Docker Engine + the Compose plugin on Ubuntu Server from Docker's
# official repository, and lets the current user run docker without sudo.
# Run once, then log out and back in.
set -euo pipefail

if ! grep -q '^ID=ubuntu' /etc/os-release; then
  echo "This script is for Ubuntu. See https://docs.docker.com/engine/install/ for other systems." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

echo
echo "Docker is installed. Log out and back in (or reboot) so you can run docker without sudo."
echo "Then check it with:  docker run --rm hello-world"
