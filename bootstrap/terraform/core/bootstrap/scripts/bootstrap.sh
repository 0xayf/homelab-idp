#!/usr/bin/env bash
set -e

log() { printf "%s %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"; }
fail() { log "ERROR: $*"; exit 1; }

# Validate required tools
for cmd in kubectl curl jq git sed; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command not found: $cmd"
done

# Validate required environment variables
REQUIRED_VARS="
  KUBECONFIG
  KUBE_CONTEXT
  GITEA_ADMIN_USER
  GITEA_ADMIN_PASSWORD
  GITEA_NAMESPACE
  PLATFORM_ORG_NAME
  PLATFORM_CORE_REPO_NAME
  PLATFORM_CORE_PATH
  ARGOCD_NAMESPACE
  APPSET_MANIFEST
"

for var in $REQUIRED_VARS; do
  eval "val=\${${var}:-}"
  [ -z "$val" ] && fail "${var} must be set"
done

# --- Port-forward setup ---
GITEA_LOCAL_PORT="${GITEA_LOCAL_PORT:-3000}"
GITEA_API_TIMEOUT_SECONDS="${GITEA_API_TIMEOUT_SECONDS:-900}"
GITEA_API_POLL_SECONDS="${GITEA_API_POLL_SECONDS:-5}"
KC="kubectl --context ${KUBE_CONTEXT}"
PF_PID=""

cleanup() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true; }
trap cleanup EXIT
trap 'fail "Script failed at line $LINENO"' ERR

start_port_forward() {
  cleanup
  log "Starting port-forward to gitea-http in namespace ${GITEA_NAMESPACE}"
  $KC port-forward -n "${GITEA_NAMESPACE}" svc/gitea-http "${GITEA_LOCAL_PORT}:3000" >/dev/null 2>&1 &
  PF_PID=$!
  sleep 1
}

GITEA_URL="http://localhost:${GITEA_LOCAL_PORT}"
GITEA_API_URL="${GITEA_URL}/api/v1"
GITEA_INTERNAL_URL="http://gitea-http.${GITEA_NAMESPACE}.svc.cluster.local:3000"
URL_ENCODED_PASSWORD=$(printf '%s' "$GITEA_ADMIN_PASSWORD" | jq -sRr @uri)

# Wait for Gitea API
deadline=$(( $(date +%s) + GITEA_API_TIMEOUT_SECONDS ))
start_port_forward
until curl -sf -o /dev/null "${GITEA_API_URL}/version"; do
  if ! kill -0 "$PF_PID" 2>/dev/null; then
    log "kubectl port-forward exited before Gitea API became available. Retrying."
    start_port_forward
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    log "Current Gitea pod status:"
    $KC -n "${GITEA_NAMESPACE}" get pods || true
    log "Current gitea-http service status:"
    $KC -n "${GITEA_NAMESPACE}" get svc gitea-http || true
    log "Current gitea-http endpoint status:"
    $KC -n "${GITEA_NAMESPACE}" get endpoints gitea-http || true
    fail "Timed out waiting for Gitea API via port-forward"
  fi

  log "Waiting for Gitea API..."
  sleep "${GITEA_API_POLL_SECONDS}"
done
log "Gitea API is available"

# --- Phase 1: Create organisation and bot user ---
log "Phase 1: Ensuring Gitea organisation and bot user exist"
ARGO_BOT_USER="argocd-bot"

# Create the organisation
org_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}")
if [ "$org_status" -eq 404 ]; then
    log "Organisation '${PLATFORM_ORG_NAME}' not found. Creating."
    curl -s -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
         -d '{"username": "'"${PLATFORM_ORG_NAME}"'"}' "${GITEA_API_URL}/orgs" > /dev/null
    log "Organisation '${PLATFORM_ORG_NAME}' created."
fi

# Create the bot user
user_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}")
if [ "$user_status" -eq 404 ]; then
    log "Bot user '${ARGO_BOT_USER}' not found. Creating."
    bot_password=$(LC_ALL=C tr -dc A-Za-z0-9 < /dev/urandom | head -c 16)
    bot_email="${ARGO_BOT_USER}-$(date +%s)@lab.local"

    json_payload=$(jq -n \
      --arg username "$ARGO_BOT_USER" \
      --arg password "$bot_password" \
      --arg email "$bot_email" \
      '{username: $username, password: $password, email: $email, must_change_password: false}')

    response=$(curl -s -w "\n%{http_code}" -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
         --data-binary "$json_payload" \
         "${GITEA_API_URL}/admin/users")

    status_code=$(echo "$response" | tail -n1)
    if [ "$status_code" -ne 201 ]; then
        echo "Error: Failed to create bot user. API returned status ${status_code}." >&2
        echo "Response body: $(echo "$response" | sed '$d')" >&2
        exit 1
    fi
    log "Bot user '${ARGO_BOT_USER}' created."
fi

# Add the bot user to the organisation's 'Owners' team
teams_json=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}/teams")
owners_team_id=$(printf '%s' "$teams_json" | jq -r '
  if type == "array" then
    .[]
  elif type == "object" and (.data | type == "array") then
    .data[]
  else
    empty
  end
  | select((.name // "" | ascii_downcase) == "owners")
  | .id
' | head -n1)
if [ -n "$owners_team_id" ]; then
    member_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/teams/${owners_team_id}/members/${ARGO_BOT_USER}")
    if [ "$member_status" -eq 404 ]; then
        log "Adding bot user to Owners team"
        curl -s -X PUT -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/teams/${owners_team_id}/members/${ARGO_BOT_USER}" > /dev/null
        log "Bot user added to Owners team"
    fi
else
    log "Owners team not found for org '${PLATFORM_ORG_NAME}'. Skipping bot team membership."
fi

# --- Phase 2: Create repositories ---
log "Phase 2: Creating Gitea repositories"

create_repo_if_not_exists() {
  local repo_name="$1"
  local repo_url_path="${PLATFORM_ORG_NAME}/${repo_name}"

  log "Ensuring ${repo_url_path} repository exists"
  repo_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/repos/${repo_url_path}")

  if [ "$repo_status" -eq 404 ]; then
    log "Repository '${repo_url_path}' not found. Creating."
    curl -s -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
         -d '{"name": "'"${repo_name}"'", "private": true}' "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}/repos" > /dev/null
    log "Repository '${repo_url_path}' created."
  else
    log "Repository '${repo_url_path}' already exists."
  fi
}

create_repo_if_not_exists "${PLATFORM_CORE_REPO_NAME}"

# --- Phase 3: Push platform-core ---
log "Phase 3: Pushing platform-core to Gitea"

init_and_push() {
  local repo_name="$1"
  local work_dir="$2"
  local commit_message="$3"

  local repo_url="http://${GITEA_ADMIN_USER}:${URL_ENCODED_PASSWORD}@localhost:${GITEA_LOCAL_PORT}/${PLATFORM_ORG_NAME}/${repo_name}.git"

  git -C "${work_dir}" init -q -b main
  git -C "${work_dir}" config user.email "bootstrap@lab.local"
  git -C "${work_dir}" config user.name "Bootstrap Script"
  git -C "${work_dir}" add .
  git -C "${work_dir}" commit -q -m "${commit_message}"
  git -C "${work_dir}" remote add origin "${repo_url}"
  git -C "${work_dir}" push -q --force -u origin main
  log "Pushed to ${PLATFORM_ORG_NAME}/${repo_name}"
}

log "Preparing platform-core"
platform_core=$(mktemp -d)
cp -r "${PLATFORM_CORE_PATH}/." "${platform_core}/"
rm -rf "${platform_core}/.git" 2>/dev/null || true

init_and_push "${PLATFORM_CORE_REPO_NAME}" "${platform_core}" "feat: Initial platform core configuration"
rm -rf "${platform_core}"

# --- Phase 4: Create argocd-repositories secret ---
log "Phase 4: Creating argocd-repositories Secret"
ARGO_TOKEN_NAME="argocd-token"
ARGO_REPO_SECRET_NAME="argocd-repositories"

tokens_json=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens")
existing_token_id=$(printf '%s' "$tokens_json" | jq -r '
  if type == "array" then
    .[] | select((.name // "") == "'"${ARGO_TOKEN_NAME}"'") | .id
  else
    empty
  end
' | head -n1)
[ -n "${existing_token_id}" ] && curl -s -X DELETE -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens/${existing_token_id}"

token_payload='{"name":"'"${ARGO_TOKEN_NAME}"'","scopes":["read:repository"]}'
token_response=$(curl -s -w "\n%{http_code}" -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
  -d "${token_payload}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens")
token_status=$(echo "$token_response" | tail -n1)
token_body=$(echo "$token_response" | sed '$d')

if [ "$token_status" -ne 201 ]; then
  fail "Failed to create Argo bot token. API returned status ${token_status}."
fi

GITEA_ARGO_TOKEN=$(printf '%s' "$token_body" | jq -r '.sha1 // empty')
[ -n "$GITEA_ARGO_TOKEN" ] || fail "Failed to parse Argo bot token from Gitea API response."

log "Applying argocd-repositories"
$KC apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGO_REPO_SECRET_NAME}
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${GITEA_INTERNAL_URL}/${PLATFORM_ORG_NAME}/${PLATFORM_CORE_REPO_NAME}.git
  username: ${ARGO_BOT_USER}
  password: ${GITEA_ARGO_TOKEN}
EOF

# --- Phase 5: Apply ApplicationSet ---
log "Phase 5: Applying platform-core ApplicationSet"
printf '%s' "${APPSET_MANIFEST}" | $KC apply -f -

log "Bootstrap complete"
