#!/usr/bin/env bash
# Registers this notebook as a self-hosted GitHub Actions runner for one app repo
# and installs it as a service that starts on boot.
#
# Usage:  ./scripts/add-runner.sh <owner/repo> <registration-token>
#
# Get the token on GitHub: app repo > Settings > Actions > Runners >
# New self-hosted runner. It is the value after --token and is valid for one hour.
#
# Personal accounts need one runner per repo, so run this once for every app repo.
# Only use it with PRIVATE repos: on a public repo, anyone opening a pull request
# could run code on this notebook.
set -euo pipefail

usage="usage: $0 <owner/repo> <registration-token>"
repo="${1:?$usage}"
token="${2:?$usage}"
if [[ $repo != */* ]]; then
  echo "$usage (for example Chico7854/my-app)" >&2
  exit 1
fi
name="home-server-${repo#*/}"
dir="$HOME/actions-runners/${repo#*/}"

if ! docker info >/dev/null 2>&1; then
  echo "Your user can't use Docker yet, so deploys would fail." >&2
  echo "Run scripts/install-docker.sh, then log out and back in, and try again." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "Unsupported CPU: $(uname -m)" >&2; exit 1 ;;
esac

version=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
  | grep -o '"tag_name": *"v[^"]*"' | grep -o '[0-9][0-9.]*')
echo "Installing GitHub Actions runner $version for $repo in $dir"

mkdir -p "$dir"
cd "$dir"
curl -fsSL -o runner.tar.gz \
  "https://github.com/actions/runner/releases/download/v${version}/actions-runner-linux-${arch}-${version}.tar.gz"
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

echo
echo "Runner '$name' is online for $repo."
echo "Check it on GitHub: https://github.com/$repo/settings/actions/runners"
