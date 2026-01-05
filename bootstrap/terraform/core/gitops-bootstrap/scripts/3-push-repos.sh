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

log "Phase 3: Pushing platform-core & platform-apps repos to Gitea"
log "Installing zip utilities"
apk add --no-cache zip unzip >/dev/null

GITEA_URL="gitea-http.gitea.svc.cluster.local:3000"
URL_ENCODED_PASSWORD=$(echo -n "$GITEA_ADMIN_PASSWORD" | jq -sRr @uri)

push_archive_to_repo() {
  local repo_name="$1"
  local archive_path="$2"
  local commit_message="$3"
  
  local repo_url_path="${PLATFORM_ORG_NAME}/${repo_name}"
  local repo_url="http://${GITEA_ADMIN_USER}:${URL_ENCODED_PASSWORD}@${GITEA_URL}/${repo_url_path}.git"
  
  log "Pushing to ${repo_url_path}"

  local work_dir=$(mktemp -d)
  local extract_dir=$(mktemp -d)

  log "Extracting archive from ${archive_path}"
  unzip -q "${archive_path}" -d "${extract_dir}"

  log "Cloning repository"
  git clone "${repo_url}" "${work_dir}"
  cd "${work_dir}"

  find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +

  cp -a "${extract_dir}/." .

  if [ -z "$(git status --porcelain)" ]; then
    log "No changes detected. Repository is already up to date."
  else
    log "Changes detected. Committing and pushing."
    git config user.email "bootstrap@lab.local"
    git config user.name "Bootstrap Script"
    git add .
    git commit -m "${commit_message}"
    git push
    log "Successfully pushed to ${repo_url_path}."
  fi

  cd /
  rm -rf "${work_dir}" "${extract_dir}"
}

log "Preparing platform-apps archive"
platform_apps_dir=$(mktemp -d)
unzip -q /archives/platform-apps.zip -d "${platform_apps_dir}"

if [ -z "${METALLB_IP_RANGE:-}" ] || [ -z "${VAULT_HOSTNAME:-}" ]; then
  fail "METALLB_IP_RANGE and VAULT_HOSTNAME must be set."
fi

log "Patching MetalLB values.yaml: __METALLB_IP_RANGE__ -> ${METALLB_IP_RANGE}"
sed -i "s|__METALLB_IP_RANGE__|${METALLB_IP_RANGE}|g" "${platform_apps_dir}/core/metallb/values.yaml"

log "Patching Vault values.yaml: __VAULT_HOSTNAME__ -> ${VAULT_HOSTNAME}"
sed -i "s|__VAULT_HOSTNAME__|${VAULT_HOSTNAME}|g" "${platform_apps_dir}/security/vault/values.yaml"

patched_archive=$(mktemp)
rm -f "${patched_archive}"
cd "${platform_apps_dir}"
zip -rq "${patched_archive}" .
cd /
rm -rf "${platform_apps_dir}"

push_archive_to_repo "${PLATFORM_APPS_REPO_NAME}" "${patched_archive}" "feat: Initial platform apps configuration"
rm -f "${patched_archive}"

push_archive_to_repo "${PLATFORM_CORE_REPO_NAME}" "/archives/platform-core.zip" "feat: Initial platform core"

log "Phase 3 complete"
