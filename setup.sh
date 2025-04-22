#!/usr/bin/env bash
set -euo pipefail # Exit on error, unset variable, or pipe failure
IFS=$'\n\t'      # Safer looping and splitting

# --- Configuration ---
ENV_FILE=".env"
TEMPLATE_FILE=".env.template"
TIMEZONE_LIST_URL="https://en.wikipedia.org/wiki/List_of_tz_database_time_zones" # Changed URL for better list

# --- Helper Functions ---
log() {
  echo "[INFO] $@"
}

warnings_occurred=0
warn() {
  echo "[WARN] $@" >&2
  warnings_occurred=1
}

error() {
  echo "[ERROR] $@" >&2
  # Clean up temp files before exiting on error
  rm -f "${ENV_FILE}.tmp."* "${ENV_FILE}.processed."*
  exit 1
}

# Function to generate a secure random hex string (32 bytes = 64 hex chars)
generate_key() {
  openssl rand -hex 32
}

# Function to safely get a value from the .env file, handling comments and whitespace
get_env_value() {
    local var_name="$1"
    local env_file="$2"
    local value=""
    if [ -f "${env_file}" ]; then
        # Grep for the variable at the start of a line, ignoring comments
        # Extract the value after the first '='
        value=$(grep -E "^\s*${var_name}\s*=" "${env_file}" | sed -n 's/^[^=]*=//p' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" | head -n 1)
    fi
    echo "$value"
}

# Function to detect system timezone
detect_timezone() {
    local detected_tz=""
    # macOS specific check
    if [[ "$(uname)" == "Darwin" ]] && command -v systemsetup &>/dev/null; then
        detected_tz=$(systemsetup -gettimezone | awk '{print $NF}')
        # Basic validation it looks like a timezone
        if [[ ! "$detected_tz" =~ ^[A-Za-z_]+/[A-Za-z_]+ ]]; then
           detected_tz=""
        fi
    # Linux check (common locations)
    elif [ -f /etc/timezone ]; then
        detected_tz=$(cat /etc/timezone)
    elif [ -L /etc/localtime ]; then
        # Example: ../usr/share/zoneinfo/America/New_York -> America/New_York
        local link_target
        link_target=$(readlink /etc/localtime)
        # Check if it contains zoneinfo path
        if [[ "$link_target" == *"/zoneinfo/"* ]]; then
             detected_tz=${link_target##*/zoneinfo/}
        fi
    fi
    # Fallback or if format is weird
    if [[ -z "$detected_tz" ]] && command -v timedatectl &>/dev/null; then
         detected_tz=$(timedatectl | grep 'Time zone' | awk '{print $3}')
    fi

    # Final basic validation
    if [[ ! "$detected_tz" =~ ^[A-Za-z_]+/[A-Za-z_]+ ]]; then
        detected_tz=""
    fi
    echo "$detected_tz"
}


# --- Main Script Logic ---

# Ensure cleanup on script exit (including normal exit)
trap 'rm -f "${ENV_FILE}.tmp."* "${ENV_FILE}.processed."*' EXIT

# 1. Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
  error "Template file '$TEMPLATE_FILE' not found. Cannot generate '$ENV_FILE'."
fi

# 2. Check if .env file exists. If not, copy from template.
#    Also handle --force flag to overwrite.
INITIAL_ENV_EXISTS=1
FORCE_OVERWRITE=0
if [ ! -f "$ENV_FILE" ]; then
  log "File '$ENV_FILE' not found. Creating from '$TEMPLATE_FILE'..."
  cp "$TEMPLATE_FILE" "$ENV_FILE"
  INITIAL_ENV_EXISTS=0
  log "Created '$ENV_FILE'."
elif [[ "$*" == *"--force"* ]]; then
  log "'--force' flag detected. Overwriting '$ENV_FILE' from '$TEMPLATE_FILE'..."
  cp "$TEMPLATE_FILE" "$ENV_FILE"
  INITIAL_ENV_EXISTS=0 # Treat as if it didn't exist initially for update logic
  FORCE_OVERWRITE=1
  log "Overwrote '$ENV_FILE'."
else
  log "Existing '$ENV_FILE' found. Will check for and add missing/placeholder variables."
fi

# 3. Process the template file to build the new .env content
log "Processing '$TEMPLATE_FILE' to update/create '$ENV_FILE'..."
added_vars=0
updated_vars=0

# Create temporary files
tmp_env_file="${ENV_FILE}.tmp.$(date +%s)"
tmp_processed_vars="${ENV_FILE}.processed.$(date +%s)"
touch "$tmp_processed_vars" # Keep track of vars handled from template

# --- Timezone Handling (Interactive) ---
detected_timezone=$(detect_timezone)
final_timezone=""
# Get timezone value from template (as default)
template_timezone=$(get_env_value "GENERIC_TIMEZONE" "$TEMPLATE_FILE")
# Get current value from existing .env (if it exists)
current_timezone=$(get_env_value "GENERIC_TIMEZONE" "$ENV_FILE")

# Decide if we need to ask the user
ask_timezone=0
if [ $FORCE_OVERWRITE -eq 1 ]; then
    ask_timezone=1 # Always ask if forcing overwrite
elif [ -z "$current_timezone" ]; then
    ask_timezone=1 # Ask if missing from current .env
elif [ "$current_timezone" == "{{GENERIC_TIMEZONE_PLACEHOLDER}}" ]; then # Example placeholder
    ask_timezone=1 # Ask if it's a placeholder
elif [ "$current_timezone" == "$template_timezone" ] && [ $INITIAL_ENV_EXISTS -eq 1 ]; then
    # Ask if current value is same as template default (and .env existed)
    # This allows user to change from the default easily on subsequent runs
    ask_timezone=1
fi

if [ $ask_timezone -eq 1 ]; then
    log "Configuring Timezone (GENERIC_TIMEZONE)..."
    if [ -n "$detected_timezone" ]; then
        read -p "Detected timezone: \"$detected_timezone\". Use this? [Y/n] or enter new: " tz_input
        # Default to detected if user presses Enter
        tz_input=${tz_input:-Y}
        case "$tz_input" in
            [Yy]* ) final_timezone="$detected_timezone"; log "Using detected timezone: $final_timezone" ;;
            [Nn]* ) final_timezone="" ;; # Fall through to ask manually
            *     ) final_timezone="$tz_input"; log "Using provided timezone: $final_timezone" ;; # Use user input directly
        esac
    fi

    # If detection failed, or user answered No/N, or didn't enter anything valid above
    if [ -z "$final_timezone" ]; then
        log "Could not detect timezone or you chose to enter manually."
        log "See list: $TIMEZONE_LIST_URL"
        while [ -z "$final_timezone" ]; do
            read -p "Please enter your timezone (e.g., America/New_York): " final_timezone
            if [ -z "$final_timezone" ]; then
                warn "Timezone cannot be empty. Using template default: $template_timezone"
                final_timezone="$template_timezone"
                break # Exit loop, use default
            elif [[ ! "$final_timezone" =~ ^[A-Za-z_]+/[A-Za-z_./-]+$ ]]; then
                 warn "Input \"$final_timezone\" doesn't look like a valid Olson timezone (Area/Location). Please try again."
                 final_timezone="" # Reset to prompt again
            else
                 log "Using provided timezone: $final_timezone"
                 break # Valid input, exit loop
            fi
        done
    fi
else
    # Use the existing value if we didn't need to ask
    final_timezone="$current_timezone"
    log "Preserving existing GENERIC_TIMEZONE: $final_timezone"
fi

# --- Process Template Lines ---
while IFS= read -r line || [[ -n "$line" ]]; do
    # Preserve comments and empty lines from template
    if [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]]; then
        echo "$line" >> "$tmp_env_file"
        continue
    fi

    # Extract variable name and template value (VAR=VALUE)
    if [[ "$line" =~ ^\s*([^=\s]+)\s*=\s*(.*)\s*$ ]]; then
        var_name="${BASH_REMATCH[1]}"
        template_value="${BASH_REMATCH[2]}"
        # Remove potential surrounding quotes from template value for processing
        template_value_unquoted=$(echo "$template_value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")

        # Mark this variable as processed from the template
        echo "$var_name" >> "$tmp_processed_vars"

        # --- Handle GENERIC_TIMEZONE specially (already determined above) ---
        if [ "$var_name" == "GENERIC_TIMEZONE" ]; then
            echo "$var_name=$final_timezone" >> "$tmp_env_file"
            # Check if the final value differs from the initial current value (if .env existed)
            if [ $INITIAL_ENV_EXISTS -eq 1 ] && [ "$current_timezone" != "$final_timezone" ] && [ "$current_timezone" != "{{GENERIC_TIMEZONE_PLACEHOLDER}}" ]; then
                 # Only count as updated if it changed from a real value
                 if [[ -n "$current_timezone" && "$current_timezone" != "$template_timezone" ]]; then
                    updated_vars=$((updated_vars + 1))
                 elif [[ -z "$current_timezone" && -n "$final_timezone" ]]; then
                    added_vars=$((added_vars + 1))
                 fi
            elif [ $INITIAL_ENV_EXISTS -eq 0 ]; then
                 added_vars=$((added_vars + 1))
            fi
            continue # Skip normal processing for timezone
        fi
        # --- End of special TIMEZONE handling ---

        # Check if variable exists in the *current* .env file
        current_value=$(get_env_value "$var_name" "$ENV_FILE")
        var_exists_in_env=0
        if [ -n "$current_value" ]; then
            var_exists_in_env=1
        fi

        if [ $INITIAL_ENV_EXISTS -eq 1 ] && [ $var_exists_in_env -eq 1 ]; then
            # Variable exists in the original .env
            needs_update=0
            generated_value=""

            # Check if the current value is a known placeholder that needs replacing
            if [[ "$current_value" == *"{{POSTGRES_PASSWORD_PLACEHOLDER}}"* ]]; then
                generated_value=$(generate_key)
                needs_update=1
                log "Generating new POSTGRES_PASSWORD for existing placeholder variable '$var_name'."
            elif [[ "$current_value" == *"{{BROWSERLESS_TOKEN_PLACEHOLDER}}"* ]]; then
                 generated_value=$(generate_key)
                 needs_update=1
                 log "Generating new BROWSERLESS_TOKEN for existing placeholder variable '$var_name'."
             # Add more placeholder checks here if needed
            fi

            # Write the updated or existing value to the temp file
            if [[ "$needs_update" -eq 1 ]]; then
                 echo "$var_name=$generated_value" >> "$tmp_env_file"
                 updated_vars=$((updated_vars + 1))
            else
                # Keep the existing value from the original .env
                echo "$var_name=$current_value" >> "$tmp_env_file"
            fi
        else
            # Variable missing from .env OR .env didn't exist initially OR was overwritten,
            # so add from template (and generate if placeholder)
            value_to_add="$template_value_unquoted" # Use unquoted value for checks
            is_placeholder=0

            # Generate value if it's a known placeholder
            case "$value_to_add" in
                *"{{POSTGRES_PASSWORD_PLACEHOLDER}}"*)
                    value_to_add=$(generate_key); is_placeholder=1
                    if [ $INITIAL_ENV_EXISTS -eq 1 ]; then log "Variable '$var_name' missing or placeholder. Generating new POSTGRES_PASSWORD." ; else log "Generating POSTGRES_PASSWORD." ; fi
                    ;;
                *"{{BROWSERLESS_TOKEN_PLACEHOLDER}}"*)
                    value_to_add=$(generate_key); is_placeholder=1
                    if [ $INITIAL_ENV_EXISTS -eq 1 ]; then log "Variable '$var_name' missing or placeholder. Generating new BROWSERLESS_TOKEN." ; else log "Generating BROWSERLESS_TOKEN." ; fi
                    ;;
                 # Add more generation cases if needed
            esac

            # Count as added if it wasn't in the original env or was a placeholder
            if [ $INITIAL_ENV_EXISTS -eq 0 ] || [ $var_exists_in_env -eq 0 ] || [ $is_placeholder -eq 1 ]; then
                 added_vars=$((added_vars + 1))
                 if [ $INITIAL_ENV_EXISTS -eq 1 ] && [ $is_placeholder -eq 0 ]; then
                     log "Variable '$var_name' missing from '$ENV_FILE'. Adding from template."
                 fi
            fi

            # Write the new variable (generated or from template) to the temp file
            echo "$var_name=$value_to_add" >> "$tmp_env_file"
        fi
    else
         # Line doesn't match VAR=VALUE, write it as is (likely comment/empty line)
         echo "$line" >> "$tmp_env_file"
    fi
done < "$TEMPLATE_FILE"

# 4. Add any remaining variables from the original .env that weren't in the template
vars_preserved=0
if [ $INITIAL_ENV_EXISTS -eq 1 ] && [ $FORCE_OVERWRITE -eq 0 ]; then
    added_preserved_header=0
    # Read original .env again
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^\s*# ]] || [[ -z "$line" ]]; then
            continue
        fi
        # Extract variable name
        if [[ "$line" =~ ^\s*([^=\s]+)\s*= ]]; then
            var_name="${BASH_REMATCH[1]}"
            # Check if this variable was processed from the template file
            if ! grep -q -x -F "$var_name" "$tmp_processed_vars"; then
                 if [ $added_preserved_header -eq 0 ]; then
                     echo "" >> "$tmp_env_file"
                     echo "# --- Variables preserved from existing .env (not in template) ---" >> "$tmp_env_file"
                     added_preserved_header=1
                 fi
                # If not processed, append the original line to the temp file
                echo "$line" >> "$tmp_env_file"
                # Avoid warning if the value is empty
                value_part="${line#*=}"
                if [ -n "$value_part" ]; then
                    warn "Variable '$var_name' exists in original '$ENV_FILE' but not in '$TEMPLATE_FILE'. It has been preserved."
                    vars_preserved=$((vars_preserved + 1))
                else
                    # Silently preserve empty variables not in template
                    : # No-op
                fi
            fi
        fi
    done < "$ENV_FILE"
fi

# 5. Replace the old .env file with the temporary one
mv "$tmp_env_file" "$ENV_FILE"
# tmp_processed_vars is removed by trap EXIT
log "Finished updating '$ENV_FILE'."

# 6. Report changes
if [ "$added_vars" -gt 0 ]; then
    log "Added/Generated $added_vars variable(s)."
fi
if [ "$updated_vars" -gt 0 ]; then
    # Don't use warn here, it's expected info
    log "Updated $updated_vars placeholder variable(s) with generated values."
fi
if [ "$vars_preserved" -gt 0 ]; then
    log "Preserved $vars_preserved non-empty variable(s) from the original '$ENV_FILE' that were not in the template."
fi

# Only report 'up-to-date' if no changes *and* .env existed initially
if [ "$added_vars" -eq 0 ] && [ "$updated_vars" -eq 0 ] && [ "$vars_preserved" -eq 0 ] && [ $INITIAL_ENV_EXISTS -eq 1 ]; then
    log "'$ENV_FILE' is already up-to-date with '$TEMPLATE_FILE'."
fi

if [ $warnings_occurred -eq 1 ]; then
     log "Please review [WARN] messages above."
fi

log "Setup script finished. '$ENV_FILE' is ready."
log "You can now start the services using: docker compose up -d"

exit 0 