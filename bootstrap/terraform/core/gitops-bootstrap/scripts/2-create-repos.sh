#!/bin/sh
set -e

log() {
  printf "%s %s\n" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

trap 'fail "Script failed at line $LINENO"' ERR

log "Phase 2: Creating Gitea repositories"
GITEA_API_URL="http://gitea-http.gitea.svc.cluster.local:3000/api/v1"

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

create_repo_if_not_exists "${PLATFORM_APPS_REPO_NAME}"
create_repo_if_not_exists "${PLATFORM_CORE_REPO_NAME}"

log "Phase 2 complete"
