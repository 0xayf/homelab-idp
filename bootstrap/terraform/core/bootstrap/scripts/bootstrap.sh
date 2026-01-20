#!/bin/sh
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
KC="kubectl --context ${KUBE_CONTEXT}"
PF_PID=""

cleanup() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true; }
trap cleanup EXIT
trap 'fail "Script failed at line $LINENO"' ERR

log "Starting port-forward to gitea-http in namespace ${GITEA_NAMESPACE}"
$KC port-forward -n "${GITEA_NAMESPACE}" svc/gitea-http "${GITEA_LOCAL_PORT}:3000" >/dev/null 2>&1 &
PF_PID=$!

GITEA_URL="http://localhost:${GITEA_LOCAL_PORT}"
GITEA_API_URL="${GITEA_URL}/api/v1"
GITEA_INTERNAL_URL="http://gitea-http.${GITEA_NAMESPACE}.svc.cluster.local:3000"
URL_ENCODED_PASSWORD=$(printf '%s' "$GITEA_ADMIN_PASSWORD" | jq -sRr @uri)

# Wait for Gitea API
i=0
until curl -sf -o /dev/null "${GITEA_API_URL}/version"; do
  i=$((i+1))
  [ "$i" -ge 60 ] && fail "Timed out waiting for Gitea API via port-forward"
  log "Waiting for Gitea API..."
  sleep 5
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
owners_team_id=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}/teams" | jq -r '.[] | select(.name | ascii_downcase == "owners") | .id')
if [ -n "$owners_team_id" ]; then
    member_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/teams/${owners_team_id}/members/${ARGO_BOT_USER}")
    if [ "$member_status" -eq 404 ]; then
        log "Adding bot user to Owners team"
        curl -s -X PUT -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/teams/${owners_team_id}/members/${ARGO_BOT_USER}" > /dev/null
        log "Bot user added to Owners team"
    fi
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

existing_token_id=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens" | jq -r '.[] | select(.name=="'"${ARGO_TOKEN_NAME}"'") | .id')
[ -n "${existing_token_id}" ] && curl -s -X DELETE -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens/${existing_token_id}"

token_payload='{"name":"'"${ARGO_TOKEN_NAME}"'","scopes":["read:repository"]}'
GITEA_ARGO_TOKEN=$(curl -s -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
  -d "${token_payload}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens" | jq -r .sha1)

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
