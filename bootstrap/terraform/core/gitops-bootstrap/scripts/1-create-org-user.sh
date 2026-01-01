#!/bin/sh
set -e
echo "--> Phase 1: Ensuring Gitea organisation and bot user exist..."
GITEA_API_URL="http://gitea-http.gitea.svc.cluster.local:3000/api/v1"
ARGO_BOT_USER="argocd-bot"

until curl -s -f -o /dev/null "http://gitea-http.gitea.svc.cluster.local:3000/api/v1/version"; do
    echo "Waiting for Gitea API..."
    sleep 5
done

# Create the organisation
org_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}")
if [ "$org_status" -eq 404 ]; then
    echo "Organisation '${PLATFORM_ORG_NAME}' not found. Creating..."
    curl -s -X POST -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" -H "Content-Type: application/json" \
         -d '{"username": "'"${PLATFORM_ORG_NAME}"'"}' "${GITEA_API_URL}/orgs" > /dev/null
fi

# Create the bot user
user_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/users/${ARGO_BOT_USER}")
if [ "$user_status" -eq 404 ]; then
    echo "Bot user '${ARGO_BOT_USER}' not found. Creating..."
    bot_password=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
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
fi

# Add the bot user to the organisation's 'Owners' team
owners_team_id=$(curl -s -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/orgs/${PLATFORM_ORG_NAME}/teams" | jq -r '.[] | select(.name | ascii_downcase == "owners") | .id')
if [ -n "$owners_team_id" ]; then
    member_status=$(curl -s -o /dev/null -w "%{http_code}" -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/teams/${owners_team_id}/members/${ARGO_BOT_USER}")
    if [ "$member_status" -eq 404 ]; then
        echo "Adding bot user to Owners team..."
        curl -s -X PUT -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASSWORD}" "${GITEA_API_URL}/teams/${owners_team_id}/members/${ARGO_BOT_USER}" > /dev/null
    fi
fi