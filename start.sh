#!/usr/bin/env bash
set -euo pipefail # Exit on error, unset variable, or pipe failure
IFS=$'\n\t'      # Safer looping and splitting

# --- Configuration ---
ENV_FILE=".env"
TEMPLATE_FILE=".env.template"

# --- Helper Functions ---
log() {
  echo "[INFO] $@"
}

warn() {
  echo "[WARN] $@" >&2
}

error() {
  echo "[ERROR] $@" >&2
  exit 1
}

# Function to generate a secure random hex string (32 bytes = 64 hex chars)
generate_key() {
  openssl rand -hex 32
}

# --- Main Script ---

# 1. Check for Docker and Docker Compose
log "Checking prerequisites..."
for cmd in docker docker-compose; do
  if ! command -v $cmd &>/dev/null; then
    error "'$cmd' command not found. Please install Docker and Docker Compose (v2+ recommended)."
  fi
done
log "Docker & Docker Compose found."

# 2. Create .env from template if it doesn't exist
if [ ! -f "$ENV_FILE" ]; then
  log "File '$ENV_FILE' not found. Generating from '$TEMPLATE_FILE'..."
  if [ ! -f "$TEMPLATE_FILE" ]; then
    error "Template file '$TEMPLATE_FILE' not found. Cannot generate '$ENV_FILE'."
  fi

  # Generate the required API keys
  GENERATED_ANYTHINGLLM_KEY=$(generate_key)
  GENERATED_GRAPHITI_KEY=$(generate_key)
  GENERATED_NEO4J_PASSWORD=$(generate_key) # Generate Neo4j password

  # Copy template and replace placeholders
  cp "$TEMPLATE_FILE" "$ENV_FILE"
  # Use sed -i for in-place editing. The '' argument handles macOS compatibility.
  sed -i'' -e "s|{{ANYTHINGLLM_INITIAL_ADMIN_KEY_PLACEHOLDER}}|$GENERATED_ANYTHINGLLM_KEY|g" "$ENV_FILE"
  sed -i'' -e "s|{{GRAPHITI_API_KEY_PLACEHOLDER}}|$GENERATED_GRAPHITI_KEY|g" "$ENV_FILE"
  sed -i'' -e "s|{{NEO4J_PASSWORD_PLACEHOLDER}}|$GENERATED_NEO4J_PASSWORD|g" "$ENV_FILE" # Replace Neo4j password placeholder

  # Prompt for OpenAI API Key if using the default
  if grep -q '^OPENAI_API_KEY="unused"' "$ENV_FILE"; then
    echo ""
    read -p "Graphiti requires an OpenAI API key for validation. Do you want to provide one now? (y/N): " -r provide_openai_key
    if [[ "$provide_openai_key" =~ ^[Yy]$ ]]; then
      read -sp "Enter your OpenAI API Key: " user_openai_key
      echo "" # Newline after secret input
      if [ -n "$user_openai_key" ]; then
        # Use a different delimiter for sed in case the key contains slashes
        sed -i'' -e "s|^OPENAI_API_KEY=\"unused\"|OPENAI_API_KEY=\"$user_openai_key\"|" "$ENV_FILE"
        log "OPENAI_API_KEY updated in 	$ENV_FILE."
      else
        warn "No key entered. Keeping default 'unused'. You may need to edit 	$ENV_FILE manually later if OpenAI features are needed."
      fi
    else
      warn "Keeping default OPENAI_API_KEY=\"unused\". You may need to edit 	$ENV_FILE manually later if OpenAI features are needed."
    fi
  fi

  log "Successfully generated '$ENV_FILE' with new API keys and Neo4j password."
  warn "IMPORTANT: Review the generated '$ENV_FILE'."
  warn "  - If using AnythingLLM authentication (AUTH_MODE=true), use the generated ANYTHINGLLM_INITIAL_ADMIN_KEY for your first login."
  warn "  - If using OpenAI features via Graphiti, replace the default OPENAI_API_KEY=\"unused\" with your actual key."
else
  log "Existing '$ENV_FILE' found. Using it."
fi

# 3. Load environment variables from .env file
# Ensures docker-compose uses the values from the .env file
log "Loading environment variables from '$ENV_FILE'..."
set -o allexport # Export all variables defined from now on
# shellcheck source=.env
source "$ENV_FILE"
set +o allexport # Stop exporting variables

# 3b. Validate required environment variables
log "Validating required environment variables..."
required_vars=("GRAPHITI_API_KEY" "NEO4J_PASSWORD" "OPENAI_API_KEY") # Added OPENAI_API_KEY
missing_vars=()
for var in "${required_vars[@]}"; do
  # Check if the variable is unset or empty
  if [ -z "${!var+x}" ] || [ -z "${!var}" ]; then
    missing_vars+=("$var")
  fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
  error "The following required environment variables are missing or empty in 	$ENV_FILE:	 ${missing_vars[*]}
  Please set them manually."
fi
log "Required environment variables are set."

# 4. Start services using Docker Compose
log "Starting services via docker-compose..."
docker-compose up -d --remove-orphans # Start in detached mode, remove old containers if config changed

log "Services are starting up in the background."
log "You can monitor logs using: docker-compose logs -f"
echo ""
log "Access services:"
log "  AnythingLLM UI: http://localhost:3001"
log "  Graphiti API:   http://localhost:8080 (Requires API Key: ${GRAPHITI_API_KEY})"
log "  Qdrant API:     http://localhost:6333"
echo ""
log "Setup complete!"

exit 0
