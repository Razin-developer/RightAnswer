#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo: sudo bash deploy/scripts/bootstrap-ubuntu.sh"
  exit 1
fi

rm -f /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y ca-certificates curl git git-lfs gnupg nginx ufw certbot python3-certbot-nginx
git lfs install --system || git lfs install

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
case "${ID}" in
  ubuntu|debian)
    docker_repo="${ID}"
    ;;
  *)
    echo "Unsupported distribution: ${PRETTY_NAME:-${ID}}"
    exit 1
    ;;
esac

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${docker_repo} ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker
systemctl enable --now nginx

if ! swapon --show | grep -q /swapfile; then
  rm -f /swapfile
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swap_enabled=0
  if swapon /swapfile; then
    swap_enabled=1
  else
    rm -f /swapfile
    dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    if swapon /swapfile; then
      swap_enabled=1
    fi
  fi

  if [[ "${swap_enabled}" -eq 1 ]]; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  else
    rm -f /swapfile
    echo "Warning: swapfile could not be enabled on this filesystem. Continuing without swap."
  fi
fi

ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "Bootstrap complete. Log out/in if you add a non-root user to the docker group later."
