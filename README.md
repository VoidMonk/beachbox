# Beachbox

A really simple configurator for hassle-free self-hosting of a web app or API on a server.

Beachbox makes it super easy to host an auto-updating app (containerized) on a virtual or bare-metal server of any size at a fraction of the cost compared to cloud platforms, with blazing fast performance, full control, and no vendor lock-in.

A single server for a single web service is powerful and reliable enough for most production use-cases. No AWS, Heroku or Kubernetes required for an app even with thousands of users.

## Features

* Self-host a web app or API in any language/framework on your own server
* Assign domain name(s) to the app
* Automatic HTTPS for domain name(s)
* Automatic build and publishing of app on changes (optional, via GitHub Actions)
* Automatic app deployment (near instant and zero-downtime)
* Persistent database (SQLite) and/or file system support (optional, via mounted volumes)

## Requirements

* Domain name(s) for the app
* A server (VM, VPS or bare-metal) with minimum 2GB RAM, 1 CPU and 40GB storage ([Vultr](https://www.vultr.com/) or [Hetzner](https://www.hetzner.com/) recommended for servers, or use any other provider). For domain mapping and SSL certificate provisioning, add an `A` or `AAAA` type DNS record in your domain provider's control panel to point the domain name(s) to the server IP address.
* Docker Engine and Compose plugin installed on server running Linux (all pre-installed if using a Docker image on Vultr or Hetzner)
* GitHub for app repo (private or public) and packages

## Usage

1. Optional: Push code and Dockerfile to app repo. Then, copy the provided build-publish workflow to the repo, review/edit if needed, and push a commit or manually run the workflow to publish a package (container image) the first time.

2. Fetch the configurator shell script (details below) on the server and run it:

    ```sh
    wget -q https://github.com/VoidMonk/beachbox/raw/main/beachbox.sh
    chmod +x beachbox.sh
    ./beachbox.sh
    ```

    Follow the prompts to have the Docker Compose file, `Caddyfile` and their common single `.env` file generated.

    Then, start all containers:

    ```sh
    docker compose up -d
    ```

    Within a few seconds your app will be deployed and accessible over HTTPS.

3. Create these in GitHub repo settings for app container auto-update (via Watchtower HTTP API):

    Variable:
    ```conf
    WATCHTOWER_URL = https://HOSTNAME/package/update
    ```
    *(change HOSTNAME to domain name)*

    Secret:
    ```conf
    WATCHTOWER_TOKEN = ######
    ```
    *(change placeholder to the same strong random string used with configurator script)*

    Pushed commits or manually run workflow will publish latest package and auto-update the app container.

## Components

* **Configurator shell script** - an interactive tool that generates necessary config files and includes relevant containers for a ready-to-run multi-container environment. It generates:
    * Docker Compose file with..
        - [Caddy](https://github.com/caddyserver/caddy) web server (reverse proxy + automatic HTTPS)
        - [Watchtower](https://github.com/nicholas-fedor/watchtower/) (periodic and triggered container auto-updates)
        - your app container
    * `Caddyfile` for Caddy
    * A common single `.env` file

* **GitHub Actions workflow** - a CI/CD workflow to build and publish app container image to GitHub packages (container registry), and trigger app container auto-update (via Watchtower HTTP API).

## Tips

* Change public DNS resolvers on server:

    ```sh
    nano /etc/systemd/resolved.conf
    ```

    Change or add `DNS` to Cloudflare DNS and `FallbackDNS` to Google DNS..

    ```conf
    DNS=1.1.1.1 1.0.0.1
    FallbackDNS=8.8.8.8 8.8.4.4
    ```

    Then, apply changes with..

    ```sh
    sudo systemctl restart systemd-resolved
    ```

* Get the latest built commit Id in the app as an environment variable through a pre-set build argument in app Dockerfile:

    ```sh
    ARG GIT_COMMIT_SHA
    ENV COMMIT_SHA=$GIT_COMMIT_SHA
    ```
