# AI Starter Kit: AnythingLLM + Graphiti Shared Memory

This repository provides a simple way to set up a self-hosted AI environment using Docker Compose, featuring:

*   **AnythingLLM:** A powerful RAG (Retrieval-Augmented Generation) platform for chatting with documents, data, and more.
*   **Graphiti:** A memory system acting as a central hub, storing conversation history and context accessible by multiple AI tools.
*   **Qdrant:** A high-performance vector database used by Graphiti to store and search embeddings efficiently.

The core idea is that AnythingLLM (and potentially other tools like AI IDE extensions) write memories to Graphiti, creating a shared context layer.

## Prerequisites

*   **Docker:** [Install Docker](https://docs.docker.com/engine/install/)
*   **Docker Compose:** Usually included with Docker Desktop, or [install separately](https://docs.docker.com/compose/install/). (v2+ recommended)
*   **Git:** To clone this repository.
*   **OpenSSL:** Usually pre-installed on Linux/macOS. Needed by `start.sh` to generate secure keys. (On Windows, Git Bash often includes it).

## Quickstart

1.  **Clone the repository:**
    ```bash
    git clone <your-repo-url> ai-starter
    cd ai-starter
    ```

2.  **Run the setup script:**
    ```bash
    chmod +x start.sh
    ./start.sh
    ```
    *   This script will check prerequisites.
    *   If `.env` doesn't exist, it will generate it from `.env.template`, creating secure random API keys for AnythingLLM (initial admin) and Graphiti.
    *   It will then start all services using `docker-compose up -d`.

3.  **Access Services:**
    *   **AnythingLLM UI:** [http://localhost:3001](http://localhost:3001)
        *   If you left `AUTH_MODE="true"` in `docker-compose.yml` (recommended for security), your *first login* will require the `ANYTHINGLLM_INITIAL_ADMIN_KEY` found in your generated `.env` file. Use this key as the password for the default `admin` user or follow UI prompts.
    *   **Graphiti API:** [http://localhost:8080](http://localhost:8080)
        *   Requires the `GRAPHITI_API_KEY` (found in `.env`) for authentication (e.g., in the `Authorization: Bearer <key>` header or via specific client configurations).
    *   **Qdrant API:** [http://localhost:6333](http://localhost:6333)

## Configuration

*   **`.env` file:** Contains generated API keys and connection details. **Do not commit this file to Git.** Modify it if you need to change ports or use existing keys.
*   **`docker-compose.yml`:** Defines the services, ports, volumes, and environment variables. You can adjust settings like `AUTH_MODE` for AnythingLLM here.
*   **`.env.template`:** The template used to create `.env` on the first run.

## Using Shared Memory

*   **AnythingLLM:** Is pre-configured in `docker-compose.yml` to use Graphiti as its memory backend via the Memory Connector Plugin (MCP). Chats and context managed within AnythingLLM will be stored in Graphiti.
*   **Other Tools (Cursor, Goose, Custom Scripts):** To access the shared memory:
    *   Point them to the Graphiti API endpoint: `http://localhost:8080/api/v1/memory` (or the relevant Graphiti endpoint for their integration).
    *   Provide the `GRAPHITI_API_KEY` from your `.env` file for authentication.
    *   Optionally specify a namespace if you want to segment memories (e.g., per project).

## Stopping Services

```bash
docker-compose down
