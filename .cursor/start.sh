#!/usr/bin/env bash
# Per-boot startup for the Beachbox Cloud Agent environment.
# Starts the Docker daemon (needed by beachbox.sh and `docker compose`) and
# returns once the daemon is ready. Idempotent: does nothing if dockerd is
# already responding.
set -o errexit
set -o nounset
set -o pipefail

DOCKERD_LOG=/var/log/beachbox-dockerd.log

if sudo docker info >/dev/null 2>&1; then
    echo "Docker daemon already running."
    exit 0
fi

echo "Starting Docker daemon..."
sudo rm -f /var/run/docker.pid
# Run dockerd as root; root owns the log redirect (SC2024-safe). Log lives
# under /var/log because fs.protected_regular blocks root from reopening
# non-root-owned files in world-writable dirs like /tmp.
sudo sh -c "nohup dockerd >$DOCKERD_LOG 2>&1 &"

for _ in $(seq 1 30); do
    if sudo docker info >/dev/null 2>&1; then
        echo "Docker daemon is ready ($(sudo docker info --format '{{.ServerVersion}}, storage driver {{.Driver}}'))."
        exit 0
    fi
    sleep 1
done

echo "Docker daemon failed to become ready within 30s. Last log lines:" >&2
sudo tail -n 20 "$DOCKERD_LOG" >&2 || true
exit 1
