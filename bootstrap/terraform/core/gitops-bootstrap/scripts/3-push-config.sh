#!/bin/sh
set -e

echo "--> Phase 3: Cloning homelab-idp..."
PLATFORM_SOURCE_REPO="https://github.com/0xayf/homelab-idp.git"
PLATFORM_SOURCE_BRANCH="main"

platform_dir=$(mktemp -d)

git clone --depth 1 --branch "${PLATFORM_SOURCE_BRANCH}" \
  "${PLATFORM_SOURCE_REPO}" "${platform_dir}"

if [ -z "${METALLB_IP_RANGE:-}" ] || [ -z "${VAULT_HOSTNAME:-}" ]; then
  echo "Error: METALLB_IP_RANGE and VAULT_HOSTNAME must be set." >&2
  exit 1
fi

sed -i "s|__METALLB_IP_RANGE__|${METALLB_IP_RANGE}|g" "${platform_dir}/platform/core/metallb/values.yaml"
sed -i "s|__VAULT_HOSTNAME__|${VAULT_HOSTNAME}|g" "${platform_dir}/platform/security/vault/values.yaml"

rm -rf /platform
mkdir -p /platform
cp -a "${platform_dir}/platform/." /platform/


cd /
rm -rf "${platform_dir}"

echo "--> Phase 4: Cloning local Gitea ${PLATFORM_ORG_NAME}/${PLATFORM_REPO_NAME} repository..."
GITEA_URL="gitea-http.gitea.svc.cluster.local:3000"
REPO_URL_PATH="${PLATFORM_ORG_NAME}/${PLATFORM_REPO_NAME}"

gitea_dir=$(mktemp -d)

URL_ENCODED_PASSWORD=$(echo -n "$GITEA_ADMIN_PASSWORD" | jq -sRr @uri)
repo_url="http://${GITEA_ADMIN_USER}:${URL_ENCODED_PASSWORD}@${GITEA_URL}/${REPO_URL_PATH}.git"

git clone "${repo_url}" "${gitea_dir}"
cd "${gitea_dir}"

echo "--> Phase 5: Pushing homelab-idp/platform applications..."
find . -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -aL /platform/. .

if [ -z "$(git status --porcelain)" ]; then
    echo "No changes detected. Repository is already up to date."
else
    echo "Changes detected. Committing and pushing..."
    git config user.email "bootstrap@lab.local"
    git config user.name "Bootstrap Script"
    git add .
    git commit -m "feat: Initial platform configuration"
    git push
fi

cd /
rm -rf "${gitea_dir}"