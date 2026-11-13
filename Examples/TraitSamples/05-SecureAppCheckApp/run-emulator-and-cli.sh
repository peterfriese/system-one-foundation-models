#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${SCRIPT_DIR}/backend"
FUNCTIONS_DIR="${BACKEND_DIR}/functions"
SECRET_FILE="${FUNCTIONS_DIR}/.secret.local"

PROJECT_ID="my-secure-project"
PROVIDER="jev"

# Parse optional --provider <jev|laya|clef|openai|gemini|gateway> while forwarding all args to Swift CLI
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
    if [ "${ARGS[$i]}" = "--provider" ] && [ $((i + 1)) -lt ${#ARGS[@]} ]; then
        PROVIDER="$(echo "${ARGS[$((i + 1))]}" | tr '[:upper:]' '[:lower:]')"
    fi
done

ENDPOINT_URL="http://127.0.0.1:5001/${PROJECT_ID}/us-central1/systemone"
MAX_POLL_SECONDS=30

echo "================================================================="
echo "  05-SecureAppCheckApp: Local Firebase Emulator & CLI Runner     "
echo "  Selected Provider: ${PROVIDER}                                 "
echo "================================================================="

has_valid_var() {
    local var_name="$1"
    local val="${!var_name:-}"
    if [ -n "${val}" ] && [ "${val}" != "mock" ] && [ "${val}" != "mock-key" ]; then
        return 0
    fi
    if [ -f "${SECRET_FILE}" ]; then
        local file_val
        file_val="$(grep -E "^[[:space:]]*${var_name}[[:space:]]*=" "${SECRET_FILE}" | tail -n 1 | cut -d '=' -f 2- | tr -d '[:space:]"'"'" || true)"
        if [ -n "${file_val}" ] && [ "${file_val}" != "mock" ] && [ "${file_val}" != "mock-key" ]; then
            return 0
        fi
    fi
    return 1
}

EFFECTIVE_PROVIDER="${PROVIDER}"
if [ "${EFFECTIVE_PROVIDER}" = "gateway" ]; then
    EFFECTIVE_PROVIDER="$(echo "${DEFAULT_PROVIDER:-jev}" | tr '[:upper:]' '[:lower:]')"
fi

echo "--> Pre-flight: Verifying upstream configuration for '${EFFECTIVE_PROVIDER}'..."

HAS_CONFIG=false
REQUIRED_DESC=""
REMEDIATION_CMD=""

case "${EFFECTIVE_PROVIDER}" in
    jev)
        REQUIRED_DESC="TYPESAFE_API_KEY"
        REMEDIATION_CMD='export TYPESAFE_API_KEY="your-typesafe-api-key"'
        has_valid_var "TYPESAFE_API_KEY" && HAS_CONFIG=true
        ;;
    laya)
        REQUIRED_DESC="LAYA_UPSTREAM_URL (or LAYA_SERVE_URL)"
        REMEDIATION_CMD='export LAYA_UPSTREAM_URL="http://127.0.0.1:8080/v1/systemone"'
        (has_valid_var "LAYA_UPSTREAM_URL" || has_valid_var "LAYA_SERVE_URL") && HAS_CONFIG=true
        ;;
    clef)
        REQUIRED_DESC="CLEF_UPSTREAM_URL or (CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN)"
        REMEDIATION_CMD='export CLOUDFLARE_ACCOUNT_ID="your-account-id" CLOUDFLARE_API_TOKEN="your-cf-token"'
        if has_valid_var "CLEF_UPSTREAM_URL" || (has_valid_var "CLOUDFLARE_ACCOUNT_ID" && has_valid_var "CLOUDFLARE_API_TOKEN"); then
            HAS_CONFIG=true
        fi
        ;;
    openai)
        REQUIRED_DESC="OPENAI_API_KEY"
        REMEDIATION_CMD='export OPENAI_API_KEY="sk-..."'
        has_valid_var "OPENAI_API_KEY" && HAS_CONFIG=true
        ;;
    gemini)
        REQUIRED_DESC="GEMINI_API_KEY (or GOOGLE_API_KEY)"
        REMEDIATION_CMD='export GEMINI_API_KEY="your-gemini-api-key"'
        (has_valid_var "GEMINI_API_KEY" || has_valid_var "GOOGLE_API_KEY") && HAS_CONFIG=true
        ;;
    *)
        echo "Error: Unsupported provider '${PROVIDER}'. Expected: jev | laya | clef | openai | gemini | gateway."
        exit 1
        ;;
esac

if [ "${HAS_CONFIG}" != true ]; then
    cat <<EOF
================================================================================
  ⚠️  CONFIGURATION ERROR: MISSING ${REQUIRED_DESC}
================================================================================
  The systemone Cloud Function proxy requires valid upstream configuration for
  provider '${EFFECTIVE_PROVIDER}' to evaluate real System One decision models.
  Synthetic mock bypasses are not permitted.

  Remediation (choose one):
    1. Export in your shell before running this script:
         ${REMEDIATION_CMD}
         ./run-emulator-and-cli.sh --provider ${PROVIDER}

    2. Or configure Firebase Functions local secret file:
         # Add ${REQUIRED_DESC} to ${SECRET_FILE}
         ./run-emulator-and-cli.sh --provider ${PROVIDER}
================================================================================
EOF
    exit 1
fi

# Step 1: Check if Node.js and Firebase tools are installed
echo "--> Step 1: Checking prerequisites (node, firebase)..."

if ! command -v node >/dev/null 2>&1; then
    echo "Error: Node.js is not installed or not in PATH."
    exit 1
fi

if ! command -v firebase >/dev/null 2>&1; then
    echo "Error: Firebase CLI ('firebase') is not installed or not in PATH."
    echo "Install it via: npm install -g firebase-tools"
    exit 1
fi

NODE_VERSION=$(node -v)
FIREBASE_VERSION=$(firebase --version)
echo "Found Node.js (${NODE_VERSION}) and Firebase CLI (${FIREBASE_VERSION})."

# Ensure dependencies are installed and functions are compiled
if [ ! -d "${FUNCTIONS_DIR}/node_modules" ]; then
    echo "Installing functions npm dependencies..."
    npm --prefix "${FUNCTIONS_DIR}" install
fi

echo "Building functions TypeScript..."
npm --prefix "${FUNCTIONS_DIR}" run build

# Step 2: Check if emulator is already running on port 5001
echo "--> Step 2: Checking emulator status on port 5001..."

EMULATOR_PID=""

cleanup() {
    if [ -n "${EMULATOR_PID:-}" ]; then
        echo ""
        echo "--> Cleaning up: Terminating background Firebase Emulator (PID: ${EMULATOR_PID})..."
        kill -TERM "${EMULATOR_PID}" 2>/dev/null || true
        wait "${EMULATOR_PID}" 2>/dev/null || true
        lsof -ti :5001 | xargs kill -9 2>/dev/null || true
        echo "Emulator terminated cleanly."
    fi
}
trap cleanup EXIT INT TERM

if lsof -i :5001 >/dev/null 2>&1; then
    echo "Firebase Emulator is already running on port 5001."
else
    echo "Starting Firebase Emulator in background (functions only)..."
    pushd "${BACKEND_DIR}" >/dev/null
    firebase emulators:start --only functions --project "${PROJECT_ID}" >/dev/null 2>&1 &
    EMULATOR_PID=$!
    popd >/dev/null
    echo "Spawned emulator process with PID ${EMULATOR_PID}."
fi

# Step 3: Health-check / poll the systemone HTTP endpoint
echo "--> Step 3: Health-checking systemone endpoint at ${ENDPOINT_URL}..."
START_TIME=$(date +%s)
READY=false

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${ENDPOINT_URL}" || true)

    if [ "${HTTP_CODE}" = "405" ] || [ "${HTTP_CODE}" = "401" ] || [ "${HTTP_CODE}" = "200" ]; then
        echo "systemone Cloud Function is active and ready (HTTP status: ${HTTP_CODE}, took ${ELAPSED}s)."
        READY=true
        break
    fi

    if [ ${ELAPSED} -ge ${MAX_POLL_SECONDS} ]; then
        break
    fi

    sleep 1
done

if [ "${READY}" != true ]; then
    echo "Error: Timed out waiting for systemone endpoint to become ready after ${MAX_POLL_SECONDS}s."
    exit 1
fi

# Step 4: Run the Swift CLI app against the active emulator
echo "--> Step 4: Running Swift CLI against the emulator..."
swift run --package-path "${SCRIPT_DIR}" SecureAppCheckApp --cli --emulator "$@"

# Step 5: Report success
echo "--> Step 5: Finished successfully!"
