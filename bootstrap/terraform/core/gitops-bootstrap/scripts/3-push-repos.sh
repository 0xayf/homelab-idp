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

REQUIRED_VARS="
  METALLB_IP_RANGE
  VAULT_HOSTNAME
  MINIO_HOSTNAME
  MINIO_API_HOSTNAME
"

for var in $REQUIRED_VARS; do
  eval "val=\${${var}:-}"
  [ -z "$val" ] && fail "${var} must be set."
done

init_and_push() {
  local repo_name="$1"
  local work_dir="$2"
  local commit_message="$3"

  local repo_url="http://${GITEA_ADMIN_USER}:${URL_ENCODED_PASSWORD}@${GITEA_URL}/${PLATFORM_ORG_NAME}/${repo_name}.git"

  git -C "${work_dir}" init -q -b main
  git -C "${work_dir}" config user.email "bootstrap@lab.local"
  git -C "${work_dir}" config user.name "Bootstrap Script"
  git -C "${work_dir}" add .
  git -C "${work_dir}" commit -q -m "${commit_message}"
  git -C "${work_dir}" remote add origin "${repo_url}"
  git -C "${work_dir}" push -q -u origin main
  log "Pushed to ${PLATFORM_ORG_NAME}/${repo_name}"
}

# Patch and push platform-apps
log "Preparing platform-apps"
apps_dir=$(mktemp -d)
unzip -q /archives/platform-apps.zip -d "${apps_dir}"

log "Patching MetalLB: __METALLB_IP_RANGE__ -> ${METALLB_IP_RANGE}"
sed -i "s|__METALLB_IP_RANGE__|${METALLB_IP_RANGE}|g" "${apps_dir}/core/metallb/values.yaml"

log "Patching Vault: __VAULT_HOSTNAME__ -> ${VAULT_HOSTNAME}"
sed -i "s|__VAULT_HOSTNAME__|${VAULT_HOSTNAME}|g" "${apps_dir}/security/vault/values.yaml"

log "Patching MinIO: __MINIO_HOSTNAME__ -> ${MINIO_HOSTNAME}"
sed -i "s|__MINIO_HOSTNAME__|${MINIO_HOSTNAME}|g" "${apps_dir}/storage/minio/values.yaml"

log "Patching MinIO API: __MINIO_API_HOSTNAME__ -> ${MINIO_API_HOSTNAME}"
sed -i "s|__MINIO_API_HOSTNAME__|${MINIO_API_HOSTNAME}|g" "${apps_dir}/storage/minio/values.yaml"

init_and_push "${PLATFORM_APPS_REPO_NAME}" "${apps_dir}" "feat: Initial platform apps configuration"
rm -rf "${apps_dir}"

# Patch and push platform-core
log "Preparing platform-core"
core_dir=$(mktemp -d)
unzip -q /archives/platform-core.zip -d "${core_dir}"

log "Renaming backend.tf.post-migration -> backend.tf"
mv "${core_dir}/backend.tf.post-migration" "${core_dir}/backend.tf"

log "Patching backend.tf: __MINIO_API_HOSTNAME__ -> ${MINIO_API_HOSTNAME}"
sed -i "s|__MINIO_API_HOSTNAME__|${MINIO_API_HOSTNAME}|g" "${core_dir}/backend.tf"

init_and_push "${PLATFORM_CORE_REPO_NAME}" "${core_dir}" "feat: Initial platform core"
rm -rf "${core_dir}"

log "Phase 3 complete"
