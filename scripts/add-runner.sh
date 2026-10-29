#!/usr/bin/env bash
# Registers this notebook as a self-hosted GitHub Actions runner for one app repo.
#
# Usage:  ./scripts/add-runner.sh <owner/repo> <registration-token>
#
# Get the token on GitHub: repo > Settings > Actions > Runners > New self-hosted runner
# (it is the value after --token, valid for one hour).
#
# Personal accounts need one runner per repo, so run this once for every app repo.
# Only use it with PRIVATE repos: on a public repo, anyone opening a pull request
# could run code on this notebook.
set -euo pipefail

repo="${1:?usage: $0 <owner/repo> <registration-token>}"
token="${2:?usage: $0 <owner/repo> <registration-token>}"
name="home-server-${repo#*/}"
dir="$HOME/actions-runners/${repo#*/}"

if ! groups | grep -qw docker; then
  echo "Your user is not in the docker group yet. Run scripts/install-docker.sh and log in again." >&2
  exit 1
fi

version=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
  | grep -o '"tag_name": *"v[^"]*"' | grep -o '[0-9][0-9.]*')

mkdir -p "$dir"
cd "$dir"
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-x64-${version}.tar.gz"
tar xzf runner.tar.gz
rm runner.tar.gz

./config.sh --unattended \
  --url "https://github.com/${repo}" \
  --token "$token" \
  --name "$name" \
  --labels home-server \
  --replace

# Run as a service so it starts on boot.
sudo ./svc.sh install "$USER"
sudo ./svc.sh start

echo "Runner '$name' is online for $repo."
