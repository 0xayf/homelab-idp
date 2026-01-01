#!/bin/bash

# This script extracts the root Certificate Authority (CA) certificate for our
# lab platform. This CA is used by the cert-manager 'lab-ca-issuer' ClusterIssuer.
#
# By adding this single CA certificate to your local machine's trust store,
# all services that use certificates issued by it (ArgoCD, Gitea, etc.)
# will be automatically trusted by your browser.

CERT_MANAGER_NAMESPACE="cert-manager"
SECRET_NAME="lab-root-ca"
OUTPUT_FILE="lab-root-ca.crt"

echo "Attempting to export the root CA certificate..."
echo " - Namespace: ${CERT_MANAGER_NAMESPACE}"
echo " - Secret:    ${SECRET_NAME}"

kubectl get secret "${SECRET_NAME}" \
  --namespace "${CERT_MANAGER_NAMESPACE}" \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "${OUTPUT_FILE}"

# Check if the file was created and has content.
if [ -s "${OUTPUT_FILE}" ]; then
  echo ""
  echo "Success! Root CA certificate exported to: ${OUTPUT_FILE}"
  echo ""
  echo "Next steps:"
  echo "1. Double-click '${OUTPUT_FILE}' to open it in Keychain Access on your machine."
  echo "2. Find the certificate named 'lab-root-ca'."
  echo "3. Double-click it, expand the 'Trust' section, and set 'When using this certificate:' to 'Always Trust'."
  echo "4. Restart your browser."
else
  echo ""
  echo "Error: Failed to export the certificate. Please check the following:"
  echo "  - Is kubectl configured correctly?"
  echo "  - Is cert-manager running in the '${CERT_MANAGER_NAMESPACE}' namespace?"
  echo "  - Does the secret '${SECRET_NAME}' exist?"
fi