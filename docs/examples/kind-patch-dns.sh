#!/bin/bash
# Patch CoreDNS in a Kind cluster to resolve *.local.lab hostnames
# to the Traefik LoadBalancer IP instead of forwarding to the host's DNS.
#
# This is only needed for Kind testing — on a real cluster, DNS is handled
# by the network's DNS server.
#
# Usage: ./kind-patch-dns.sh [traefik_lb_ip] [kube_context]

set -euo pipefail

TRAEFIK_LB_IP="${1:-10.89.0.20}"
KUBE_CONTEXT="${2:-kind-homelab}"
KC="kubectl --context $KUBE_CONTEXT"

HOSTS_BLOCK="hosts {
      ${TRAEFIK_LB_IP} auth.local.lab
      ${TRAEFIK_LB_IP} cd.local.lab
      ${TRAEFIK_LB_IP} git.local.lab
      ${TRAEFIK_LB_IP} git-ssh.local.lab
      ${TRAEFIK_LB_IP} gateway.local.lab
      ${TRAEFIK_LB_IP} secrets.local.lab
      ${TRAEFIK_LB_IP} storage.local.lab
      ${TRAEFIK_LB_IP} s3.local.lab
      fallthrough
    }"

# Get current Corefile
COREFILE=$($KC -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')

# Check if already patched
if echo "$COREFILE" | grep -q "hosts {"; then
  echo "CoreDNS already patched. Skipping."
  exit 0
fi

# Insert hosts block before the kubernetes plugin using python (portable across macOS/Linux)
PATCHED=$(python3 -c "
import sys
corefile = sys.stdin.read()
hosts_block = '''$HOSTS_BLOCK'''
print(corefile.replace('kubernetes cluster.local', hosts_block + '\n    kubernetes cluster.local'))
" <<< "$COREFILE")

# Apply patched Corefile
$KC -n kube-system create configmap coredns --from-literal="Corefile=$PATCHED" --dry-run=client -o yaml | $KC apply -f -

# Restart CoreDNS to pick up the change
$KC -n kube-system rollout restart deployment coredns
$KC -n kube-system rollout status deployment coredns --timeout=30s

echo "CoreDNS patched. *.local.lab now resolves to $TRAEFIK_LB_IP"
