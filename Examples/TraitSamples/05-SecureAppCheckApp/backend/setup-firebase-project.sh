#!/usr/bin/env bash
set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${BOLD}${BLUE}======================================================${NC}"
echo -e "${BOLD}${BLUE}   Firebase App Check & System One Gateway Wizard     ${NC}"
echo -e "${BOLD}${BLUE}======================================================${NC}\n"

# 1. Prerequisite checks
echo -e "${BOLD}Step 1: Checking CLI tools...${NC}"
if ! command -v firebase &> /dev/null; then
    echo -e "${RED}Error: 'firebase' CLI is not installed.${NC}"
    echo "Install it via: npm install -g firebase-tools"
    exit 1
fi
echo -e "${GREEN}✓ Firebase CLI found (${NC}$(firebase --version)${GREEN})${NC}"

if ! command -v gcloud &> /dev/null; then
    echo -e "${YELLOW}Notice: 'gcloud' CLI not found. Secret Manager will be configured via Firebase CLI.${NC}"
fi

# 2. Select Firebase Project
echo -e "\n${BOLD}Step 2: Firebase Project Selection${NC}"
echo "Current Firebase accounts:"
firebase login:list || true

read -rp "Enter your Firebase Project ID: " PROJECT_ID
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: Project ID cannot be empty.${NC}"
    exit 1
fi

echo -e "Using project: ${BOLD}${GREEN}${PROJECT_ID}${NC}"
firebase use "$PROJECT_ID"

# 3. Configure Upstream Provider Secrets in GCP Secret Manager
echo -e "\n${BOLD}Step 3: Google Cloud Secret Manager (Multi-Provider API Keys)${NC}"
echo "API keys are stored securely in GCP Secret Manager and never bundled into the iOS/macOS client app."
echo "Configure at least one upstream provider secret (press Enter to skip unused providers):"

SECRET_NAMES=(
    "TYPESAFE_API_KEY"
    "GEMINI_API_KEY"
    "OPENAI_API_KEY"
    "CLOUDFLARE_API_TOKEN"
    "LAYA_API_KEY"
)
CONFIGURED_SECRETS=()

for SECRET_NAME in "${SECRET_NAMES[@]}"; do
    read -rsp "  ${SECRET_NAME} (leave empty to skip): " SECRET_VAL
    echo ""
    if [ -n "$SECRET_VAL" ]; then
        echo -e "  Storing ${BOLD}${SECRET_NAME}${NC} in Secret Manager..."
        if printf '%s' "$SECRET_VAL" | firebase functions:secrets:set "$SECRET_NAME" --project "$PROJECT_ID"; then
            CONFIGURED_SECRETS+=("$SECRET_NAME")
            echo -e "  ${GREEN}✓ ${SECRET_NAME} stored securely.${NC}"
        else
            echo -e "  ${YELLOW}Warning: Could not set ${SECRET_NAME} automatically. Run 'firebase functions:secrets:set ${SECRET_NAME}' manually.${NC}"
        fi
    fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "${#CONFIGURED_SECRETS[@]}" -gt 0 ]; then
    JOINED_SECRETS="$(IFS=,; echo "${CONFIGURED_SECRETS[*]}")"
    printf 'ENABLED_SECRETS=%s\n' "$JOINED_SECRETS" > "$SCRIPT_DIR/functions/.env"
    echo -e "${GREEN}✓ Recorded ENABLED_SECRETS=${JOINED_SECRETS} in functions/.env${NC}"
else
    echo -e "${YELLOW}Warning: No upstream secrets configured yet. The proxy runs strict real execution (zero mock fallbacks) and will return HTTP 500 MissingConfiguration until at least one provider secret is set via 'firebase functions:secrets:set <SECRET_NAME>' and listed in ENABLED_SECRETS.${NC}"
fi

# 4. Build TypeScript Functions
echo -e "\n${BOLD}Step 4: Building Cloud Functions...${NC}"
cd "$SCRIPT_DIR/functions"

if [ -f "package.json" ]; then
    echo "Installing function dependencies..."
    npm install
    echo "Compiling TypeScript..."
    npm run build
    echo -e "${GREEN}✓ Cloud Functions compiled successfully.${NC}"
fi

# 5. Cloud Function Deployment (`systemone` + `jevProxy` alias)
cd "$SCRIPT_DIR"
echo -e "\n${BOLD}Step 5: Cloud Function Deployment${NC}"
read -rp "Deploy 'systemone' (and 'jevProxy' alias) Cloud Functions now? [y/N]: " CONFIRM_DEPLOY

if [[ "$CONFIRM_DEPLOY" =~ ^[Yy]$ ]]; then
    echo "Deploying 2nd Gen Cloud Functions to project '$PROJECT_ID'..."
    firebase deploy --only functions --project "$PROJECT_ID"
    BASE_URL="https://us-central1-${PROJECT_ID}.cloudfunctions.net/systemone"
    echo -e "\n${GREEN}✓ Deployed successfully!${NC}"
    echo -e "Multi-Provider Gateway Endpoints:"
    echo -e "  • Default / Auto-Route: ${BOLD}${BLUE}${BASE_URL}${NC}"
    echo -e "  • Per-Provider Routes:  ${BOLD}${BLUE}${BASE_URL}/<jev|laya|clef|openai|gemini>${NC}"
    echo -e "  • Legacy Alias:         ${BOLD}${BLUE}https://us-central1-${PROJECT_ID}.cloudfunctions.net/jevProxy${NC}"
else
    echo -e "${YELLOW}Deployment deferred. You can deploy later using:${NC}"
    echo "  cd $(pwd) && firebase deploy --only functions --project \"$PROJECT_ID\""
fi

# 6. Update Client Configuration
echo -e "\n${BOLD}Step 6: Updating Client Configuration...${NC}"
CLIENT_SWIFT_VIEW="$SCRIPT_DIR/../Sources/SecureTriageView.swift"
if [ -f "$CLIENT_SWIFT_VIEW" ]; then
    sed -i.bak "s/var projectID: String = \".*\"/var projectID: String = \"$PROJECT_ID\"/g" "$CLIENT_SWIFT_VIEW" 2>/dev/null && rm -f "${CLIENT_SWIFT_VIEW}.bak" || true
    echo -e "${GREEN}✓ Updated default project ID to '$PROJECT_ID' in SecureTriageView.swift${NC}"
fi

echo -e "\n${BOLD}${GREEN}======================================================${NC}"
echo -e "${BOLD}${GREEN}               Setup Complete!                        ${NC}"
echo -e "${BOLD}${GREEN}======================================================${NC}"
echo -e "Next steps:"
echo -e "1. For Local Emulator testing: ${BLUE}./run-emulator-and-cli.sh --provider gemini${NC}"
echo -e "2. For Production App Attest setup: see ${BOLD}SETUP-PRODUCTION.md${NC}"
echo -e "3. Run the client CLI: ${BLUE}swift run --traits Remote SecureAppCheckApp --cli --provider gemini --project ${PROJECT_ID}${NC}"
