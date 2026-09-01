#!/usr/bin/env bash
# Beachbox Cloud Agent environment bootstrap (idempotent).
# Installs the toolchain needed to develop and run the Beachbox configurator:
#   - Docker Engine + Compose plugin (beachbox.sh requires both, and the
#     generated stack is exercised with `docker compose up`)
#   - shellcheck (lints beachbox.sh)
#   - fuse-overlayfs (lets Docker run nested inside the Cloud Agent VM, whose
#     /var/lib/docker sits on an overlay filesystem that rejects kernel overlay2)
# Docker itself is started per-boot by start.sh, not here.
set -o errexit
set -o nounset
set -o pipefail

export DEBIAN_FRONTEND=noninteractive

install_docker_repo() {
    if [ -f /etc/apt/sources.list.d/docker.list ]; then
        return
    fi
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    # shellcheck source=/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
}

install_packages() {
    if command -v docker >/dev/null 2>&1 \
        && docker compose version >/dev/null 2>&1 \
        && command -v shellcheck >/dev/null 2>&1 \
        && command -v fuse-overlayfs >/dev/null 2>&1; then
        echo "All required packages already present; skipping apt install."
        return
    fi
    sudo apt-get update -qq
    # --force-confold keeps our config files and avoids the interactive
    # fuse.conf conffile prompt that otherwise breaks non-interactive installs.
    sudo apt-get install -y -o Dpkg::Options::=--force-confold \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin \
        shellcheck fuse-overlayfs uidmap
}

configure_docker() {
    # Nested Docker: prefer legacy iptables and the fuse-overlayfs storage
    # driver so the daemon works on top of the VM's overlay filesystem.
    sudo update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
    sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true

    sudo mkdir -p /etc/docker
    echo '{
  "features": { "containerd-snapshotter": false },
  "storage-driver": "fuse-overlayfs"
}' | sudo tee /etc/docker/daemon.json > /dev/null

    # Let the agent's user run docker without sudo after the next login/boot.
    sudo groupadd -f docker
    sudo usermod -aG docker "$(id -un)"
}

install_docker_repo
install_packages
configure_docker

echo "Beachbox environment install complete:"
docker --version
docker compose version
shellcheck --version | sed -n '2p'
