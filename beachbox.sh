#!/bin/bash
# Beachbox - really simple configurator for quickest and easiest self-hosting of a web app or API on a server.
# Generates Docker Compose file and Caddyfile for ready-to-run multi-container environment.
# https://github.com/VoidMonk/beachbox
set -o nounset
set -o errexit

echo -e "Beachbox - app container definition generator (Docker Compose file and Caddyfile)\n"

# Check if Docker is installed
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: Docker is not installed or not in PATH."
    echo "Please install Docker before running this script."
    exit 1
fi

# Check if Docker Compose is available (standalone or as 'docker compose')
if docker compose version >/dev/null 2>&1; then
    :
elif command -v docker-compose >/dev/null 2>&1; then
    :
else
    echo "Error: Docker Compose is not installed or not in PATH."
    echo "Please install Docker Compose before running this script."
    exit 1
fi

# Login to container registry
read -n 1 -r -p "* Login to container registry? (y/n): " CR_LOGIN_ANS
echo
if [[ "$CR_LOGIN_ANS" =~ ^[Yy]$ ]]; then
    echo -e "First, create or copy existing personal token (read:packages permission) for GitHub Container Registry at https://github.com/settings/tokens \n"
    read -n 1 -s -r -p "Press any key when ready to login.."
    echo
    docker login ghcr.io
fi

# Ask for repo, app, domain details
read -p "* Enter repo owner and project (as lowercase owner/project) of app container image: " OWNER_PROJECT_ANS
if [ -z "$OWNER_PROJECT_ANS" ]; then
    echo 'Error: Owner/project cannot be blank'
    exit 1
fi

read -p "* Enter a name for app container: " APP_NAME_ANS
if [ -z "$APP_NAME_ANS" ]; then
    echo 'Error: Name cannot be blank'
    exit 1
fi

read -p "* Enter one or more domain names (space separated) for app container: " ALL_DOMAINS_ANS
if [ -z "$ALL_DOMAINS_ANS" ]; then
    echo 'Error: Domains cannot be blank'
    exit 1
fi

if [[ $ALL_DOMAINS_ANS = *" "* ]]; then
    read -p "* Enter the domain name (one of above) to use for Watchtower container update webhook: " WEBHOOK_DOMAIN_ANS
    if [ -z "$WEBHOOK_DOMAIN_ANS" ]; then
        echo 'Error: Domain cannot be blank'
        exit 1
    fi
else
    WEBHOOK_DOMAIN_ANS=$ALL_DOMAINS_ANS
fi

# Ask for Watchtower webhook token
read -s -p "* Enter the auth token (strong random string) for Watchtower webhook (HTTP API): " WEBHOOK_TOKEN_ANS
if [ -z "$WEBHOOK_TOKEN_ANS" ]; then
    echo 'Error: Token cannot be blank'
    exit 1
fi

# Start generating files
echo -e "\n\nCreating .env file.."
cat << EOF > .env
OWNER_PROJECT="$OWNER_PROJECT_ANS"
APP_NAME="$APP_NAME_ANS"
ALL_DOMAINS="$ALL_DOMAINS_ANS"
WEBHOOK_DOMAIN="$WEBHOOK_DOMAIN_ANS"
WEBHOOK_TOKEN="$WEBHOOK_TOKEN_ANS"
EOF
echo -e "env file created!\n"

echo "Creating Caddyfile.."
cat << 'EOF' > Caddyfile
# Caddyfile is auto-generated (via beachbox), mounted (via Docker Compose) and auto-loaded when its container starts
# Changes for a running container can be manually applied with 'docker exec -w /etc/caddy caddy_container_id caddy reload' (get container id with 'docker ps')

{$ALL_DOMAINS} {
    header -Via

    @adminonly {
        host {$WEBHOOK_DOMAIN}
        path /package/update
    }

    handle @adminonly {
        rewrite * /v1/update
        reverse_proxy watchtower:9000
    }

    reverse_proxy {$APP_NAME}:8080 {
        lb_try_duration 10s
        lb_try_interval 1s
    }
}
EOF
echo -e "Caddyfile created!\n"

echo "Creating Docker compose file.."
cat << 'EOF' > compose.yml
# Docker Compose file is auto-generated (via beachbox)
# Start all services with 'docker compose up -d'

services:
  # App container
  app:
    image: ghcr.io/${OWNER_PROJECT}:latest
    container_name: ${APP_NAME}
    restart: always
    ports:
      - "8080:8080"

  # Caddy (reverse proxy + HTTPS via HTTP challenge)
  caddy:
    image: caddy:latest
    container_name: caddy
    restart: always
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    env_file:
      - ./.env
    depends_on:
      - app

  # Watchtower (polling + HTTP API)
  watchtower:
    image: nickfedor/watchtower:latest
    container_name: watchtower
    restart: unless-stopped
    ports:
      - "9000:9000" # Watchtower HTTP API exposed on VM
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ~/.docker/config.json:/config.json
    environment:
      - WATCHTOWER_HTTP_API_TOKEN=${WEBHOOK_TOKEN}
    command: >
      --cleanup
      --interval 86400
      --http-api-update
      --http-api-port "9000"
      --http-api-periodic-polls
      --stop-timeout 1s
      --include-stopped
      --revive-stopped
      --rolling-restart

volumes:
  caddy_data:
  caddy_config:
EOF
echo -e "Docker compose file created!\n"

echo -e "All files created. Check files, and then start all services with 'docker compose up -d' \n"
echo -e "Access your self-hosted app at its domain name!\n"
