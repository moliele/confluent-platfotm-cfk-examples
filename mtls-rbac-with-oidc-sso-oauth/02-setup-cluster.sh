#!/usr/bin/env bash
# Run as your normal user (NOT sudo)
set -euo pipefail

if [ "$EUID" -eq 0 ]; then
  echo "ERROR: Do not run this script as root/sudo. Run as your normal user." >&2
  exit 1
fi

echo "==> Creating kind cluster..."
kind create cluster --name confluent --wait 300s
kubectl cluster-info --context kind-confluent

kubectl create namespace confluent
kubens confluent

echo "==> Cloning confluent-kubernetes-examples..."
git clone https://github.com/confluentinc/confluent-kubernetes-examples.git

cd confluent-kubernetes-examples/security/mtls-rbac-with-sso-oauth

echo ""
echo "Run the following exports in your shell before continuing:"
echo ""
echo "  export SCENARIO_HOME=\$PWD"
echo "  export CERT_HOME=\$SCENARIO_HOME/../../assets/certs/component-certs"
echo "  export ASSETS_HOME=\$SCENARIO_HOME/../../assets/certs"
echo ""
echo "If running on a VM, also run:"
echo "  export VM_IP=\$(curl -s ifconfig.me)"
echo "  export KEYCLOAK_HOST=\${VM_IP}.sslip.io"
echo "  export KEYCLOAK_BASE_URL=http://\${KEYCLOAK_HOST}:8080"
