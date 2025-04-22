# Self-Hosted AI Stack: n8n + AnythingLLM + Browserless

This repository provides a Docker Compose setup for running a useful AI and automation stack:

*   **n8n:** A powerful workflow automation tool.
*   **AnythingLLM:** An efficient RAG (Retrieval-Augmented Generation) platform.
*   **Browserless:** A headless Chrome instance for web scraping and browser automation tasks used by n8n.

It includes optional configuration for securely exposing n8n to the internet using Cloudflare Tunnel.

## Prerequisites

*   **Docker:** [Install Docker](https://docs.docker.com/engine/install/)
*   **Docker Compose:** Usually included with Docker Desktop, or [install separately](https://docs.docker.com/compose/install/). (v2+ recommended)
*   **Git:** To clone this repository.
*   **OpenSSL:** Needed by `setup.sh` to generate a secure Browserless token if one isn't provided. Usually pre-installed on Linux/macOS; often included with Git Bash on Windows.
*   **(Optional) Cloudflare Account:** Required if you want to expose n8n publicly using the included Cloudflare Tunnel configuration. A free account is sufficient.

## Setup

1.  **Clone the repository:**
    ```bash
    git clone <your-repo-url> self-hosted-ai-stack
    cd self-hosted-ai-stack
    ```

2.  **Configure Environment:**
    *   The file `.env.template` contains default settings and placeholders.
    *   Run the setup script to generate your initial `.env` file:
        ```bash
        chmod +x setup.sh
        ./setup.sh
        ```
    *   This script copies `.env.template` to `.env` (if `.env` doesn't exist) and generates a secure `BROWSERLESS_TOKEN` if one isn't already set.
    *   **Important:** Edit the generated `.env` file:
        *   Set `GENERIC_TIMEZONE` to your local timezone (e.g., `America/Denver`). Find yours [here](https://momentjs.com/timezone/).
        *   Review the generated `BROWSERLESS_TOKEN`. Keep it secret.
        *   **If using Cloudflare Tunnel (see below):** Set `N8N_PUBLIC_HOSTNAME` and `CLOUDFLARE_TUNNEL_TOKEN`.

## Cloudflare Tunnel Setup (Optional but Recommended for Public n8n Access)

This configuration allows you to securely expose n8n to the internet using a specific hostname (e.g., `n8n.yourdomain.com`), leveraging Cloudflare's free Tunnel service. Only webhook paths (`/webhook*`) will be publicly accessible; the main UI/API will be blocked at Cloudflare's edge.

**If you don't need public access to n8n, you can skip this section.** The `cloudflared` container will start but won't connect if the token is missing, and you can access services locally (see "Accessing Services").

**Cloudflare Configuration Steps:**

1.  **Prerequisites:** Ensure you have a domain managed by Cloudflare.
2.  **Create Tunnel & Get Token:**
    *   Go to your Cloudflare Dashboard -> **Zero Trust** -> **Access -> Tunnels**.
    *   Click **Create a tunnel** -> Choose **Cloudflared** connector type -> **Next**.
    *   Give your tunnel a name (e.g., `self-hosted-ai-stack`) -> **Save tunnel**.
    *   Choose **Docker** environment -> **Copy the long tunnel token** shown in the example command.
    *   Go back to your `.env` file and paste this token as the value for `CLOUDFLARE_TUNNEL_TOKEN`.
    *   Click **Next** in Cloudflare.
3.  **Configure Public Hostname:**
    *   On the "Public Hostnames" tab, click **Add a public hostname**.
    *   **Subdomain:** Enter the part *before* your domain (e.g., `n8n`).
    *   **Domain:** Select your domain.
    *   **Path:** Leave blank.
    *   **Service Type:** Select `HTTP`.
    *   **Service URL:** Enter `n8n:5678`.
    *   **(Recommended) Additional settings -> TLS:** Enable **No TLS Verify**.
    *   **Save hostname**.
    *   **Save tunnel**.
4.  **Set Public Hostname in `.env`:**
    *   Ensure the `N8N_PUBLIC_HOSTNAME` variable in your `.env` file matches the full public hostname you just configured (e.g., `n8n.yourdomain.com`).
5.  **Create WAF Rule:**
    *   Go back to the main Cloudflare Dashboard -> Select your domain -> **Security -> WAF**.
    *   Select the **Custom rules** tab -> **Create rule**.
    *   **Rule name:** `Block n8n UI/API`
    *   **Configure expression:** `(http.host eq "n8n.yourdomain.com" and not starts_with(http.request.uri.path, "/webhook"))`
        *   *Replace* `n8n.yourdomain.com` with your actual `N8N_PUBLIC_HOSTNAME`.
    *   **Then... Action:** Choose `Block`.
    *   **Deploy** the rule.

## Running the Stack

After configuring your `.env` file (and optionally Cloudflare), start the services:

```bash
docker compose up -d
```

*   This command starts all services defined in `docker-compose.yml` in detached mode.
*   If you configured Cloudflare, check the tunnel connection: `docker compose logs cloudflared`

## Accessing Services

*   **If using Cloudflare Tunnel:**
    *   **n8n Webhooks:** Accessible publicly at `https://<Your_N8N_PUBLIC_HOSTNAME>/webhook/...`
    *   **n8n UI/API:** *Not* accessible publicly (blocked by WAF rule). Access it via `http://localhost:5678` directly on the machine running Docker.
*   **If *not* using Cloudflare Tunnel:**
    *   **n8n:** `http://localhost:5678` (Accessible only on the machine running Docker. The entire n8n instance is available here).
    *   **AnythingLLM:** `http://localhost:3001`
    *   **Browserless:** Available internally for n8n. The management UI (if needed) is at `http://localhost:3100`, but requires the `BROWSERLESS_TOKEN` from `.env` for access.

## Stopping Services

```bash
docker compose down
```
This stops and removes the containers defined in the configuration.

## Notes

*   The `.env` file contains sensitive information like the Browserless token and potentially the Cloudflare token. **Do not commit `.env` to version control.** Use the `.gitignore` file provided.
*   The `n8n` service requires the `WEBHOOK_URL` environment variable (set using `N8N_PUBLIC_HOSTNAME`) to correctly construct webhook URLs in its UI, even if only accessed locally.
