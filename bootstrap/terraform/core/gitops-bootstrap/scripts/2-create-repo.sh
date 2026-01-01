#!/bin/sh
set -e
echo "--> Phase 2: Ensuring ${PLATFORM_ORG_NAME}/${PLATFORM_REPO_NAME} repository exists..."
GITEA_API_URL="http://gitea-http.gitea.svc.cluster.local:3000/api/v1"
REPO_URL_PATH="${PLATFORM_ORG_NAME}/${PLATFORM_REPO_NAME}"

repo_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/repos/${REPO_URL_PATH}")
if [ "$repo_status" -eq 404 ]; then
    echo "Repository '${REPO_URL_PATH}' not found. Creating..."
    curl -s -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
         -d '{"name": "'"${PLATFORM_REPO_NAME}"'", "private": true}' "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}/repos" > /dev/null
fi