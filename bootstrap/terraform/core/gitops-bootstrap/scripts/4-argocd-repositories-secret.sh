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

log "--> Phase 4: Creating argocd-repositories Secret"
GITEA_API_URL="http://gitea-http.gitea.svc.cluster.local:3000/api/v1"
ARGO_BOT_USER="argocd-bot"
ARGO_TOKEN_NAME="argocd-token"
ARGO_REPO_SECRET_NAME="argocd-repositories"

existing_token_id=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens" | jq -r '.[] | select(.name=="'"${ARGO_TOKEN_NAME}"'") | .id')
[ -n "${existing_token_id}" ] && curl -s -X DELETE -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens/${existing_token_id}"

token_payload='{"name":"'"${ARGO_TOKEN_NAME}"'","scopes":["read:repository"]}'
GITEA_ARGO_TOKEN=$(curl -s -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
  -d "${token_payload}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}/tokens" | jq -r .sha1)      

log "Applying argocd-repositories "
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${ARGO_REPO_SECRET_NAME}
  namespace: ${ARGO_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: http://gitea-http.gitea.svc.cluster.local:3000/${PLATFORM_ORG_NAME}/${PLATFORM_APPS_REPO_NAME}.git
  username: ${ARGO_BOT_USER}
  password: ${GITEA_ARGO_TOKEN}
EOF