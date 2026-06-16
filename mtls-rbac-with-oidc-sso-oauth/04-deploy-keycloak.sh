#!/usr/bin/env bash
# Run as your normal user (NOT sudo).
# Run AFTER 03-deploy-samba.sh and AFTER keycloak-custom.yaml is ready.
set -euo pipefail

SCENARIO_HOME="${SCENARIO_HOME:-$HOME/confluent-kubernetes-examples/security/mtls-rbac-with-sso-oauth}"
NS="${NS:-confluent}"

echo "==> Installing Confluent for Kubernetes operator..."
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm upgrade --install operator confluentinc/confluent-for-kubernetes \
  -n "$NS" --create-namespace

echo "==> Waiting for operator to be ready..."
kubectl rollout status deployment/confluent-operator -n "$NS" --timeout=180s

echo "==> Deploying Keycloak from custom manifest..."
kubectl apply -f "$SCENARIO_HOME/keycloak-custom.yaml" -n "$NS"
kubectl rollout status deployment/keycloak -n "$NS" --timeout=300s

echo "Done. Port-forward Keycloak (keep running in a separate terminal):"
echo "  kubectl port-forward --address 0.0.0.0 svc/keycloak 8080:8080 -n $NS"
