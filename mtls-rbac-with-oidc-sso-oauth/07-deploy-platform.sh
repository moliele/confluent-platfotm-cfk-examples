#!/usr/bin/env bash
# Run as your normal user (NOT sudo).
# Run AFTER 06-generate-certs-secrets.sh and AFTER confluent-platform-custom.yaml is ready.
set -euo pipefail

SCENARIO_HOME="${SCENARIO_HOME:-$HOME/confluent-kubernetes-examples/security/mtls-rbac-with-sso-oauth}"
NS="${NS:-confluent}"

echo "==> Deploying Confluent Platform..."
kubectl apply -f "$SCENARIO_HOME/confluent-platform-custom.yaml" -n "$NS"

echo "==> Waiting for kafka-0 pod to be created..."
until kubectl get pod kafka-0 -n "$NS" >/dev/null 2>&1; do
  echo "   kafka-0 not yet scheduled, waiting 10s..."
  sleep 10
done

echo "==> Waiting for kafka-0 to be ready (this takes several minutes)..."
kubectl wait pod/kafka-0 -n "$NS" --for=condition=Ready --timeout=600s

echo "==> Applying Control Center rolebinding (group /g1 -> ClusterAdmin)..."
CP_SRC="$HOME/confluent-kubernetes-examples/security/control-center-sso/controlcenter-rolebinding.yaml"
cp "$CP_SRC" "$SCENARIO_HOME/"
kubectl apply -f "$SCENARIO_HOME/controlcenter-rolebinding.yaml" -n "$NS"

echo "==> Applying OAuth client rolebinding (group /g-client-oauth -> ClusterAdmin)..."
cat <<'EOF' > "$SCENARIO_HOME/client-oauth-rolebinding.yaml"
apiVersion: platform.confluent.io/v1beta1
kind: ConfluentRolebinding
metadata:
  name: client-oauth-clusteradmin
  namespace: confluent
spec:
  principal:
    type: group
    name: /g-client-oauth
  role: ClusterAdmin
EOF
kubectl apply -f "$SCENARIO_HOME/client-oauth-rolebinding.yaml" -n "$NS"

echo "==> Applying mTLS admin client rolebinding (User:kafka.admin.local -> ClusterAdmin)..."
cat <<'EOF' > "$SCENARIO_HOME/admin-client-rolebinding.yaml"
apiVersion: platform.confluent.io/v1beta1
kind: ConfluentRolebinding
metadata:
  name: admin-client-clusteradmin
  namespace: confluent
spec:
  principal:
    type: user
    name: kafka.admin.local
  role: ClusterAdmin
EOF
kubectl apply -f "$SCENARIO_HOME/admin-client-rolebinding.yaml" -n "$NS"

echo "Done. Check pods and rolebindings:"
echo "  kubectl get pods -n $NS"
echo "  kubectl get confluentrolebinding -n $NS"
