#!/usr/bin/env bash
# Run as your normal user (NOT sudo).
# Recreates the admin-client pod with hostAliases for the external Kafka listener (port 9092).
# Run AFTER Kafka is deployed and the external LoadBalancer services exist.
set -euo pipefail

SCENARIO_HOME="${SCENARIO_HOME:-$HOME/confluent-kubernetes-examples/security/mtls-rbac-with-sso-oauth}"
NS="${NS:-confluent}"

echo "==> Resolving Kafka external service IPs..."
BOOTSTRAP_IP=$(kubectl get svc kafka-bootstrap-lb -n "$NS" -o jsonpath='{.spec.clusterIP}')
B0_IP=$(kubectl get svc kafka-0-lb -n "$NS" -o jsonpath='{.spec.clusterIP}')
B1_IP=$(kubectl get svc kafka-1-lb -n "$NS" -o jsonpath='{.spec.clusterIP}')
B2_IP=$(kubectl get svc kafka-2-lb -n "$NS" -o jsonpath='{.spec.clusterIP}')

echo "  bootstrap : $BOOTSTRAP_IP"
echo "  broker-0  : $B0_IP"
echo "  broker-1  : $B1_IP"
echo "  broker-2  : $B2_IP"

echo "==> Deleting existing admin-client pod..."
kubectl delete pod admin-client -n "$NS" --ignore-not-found

echo "==> Creating admin-client pod with hostAliases..."
cat <<EOF > "$SCENARIO_HOME/admin-client.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: admin-client
  namespace: $NS
spec:
  hostAliases:
    - ip: "$BOOTSTRAP_IP"
      hostnames: ["kafka.mydomain.example"]
    - ip: "$B0_IP"
      hostnames: ["b0.mydomain.example"]
    - ip: "$B1_IP"
      hostnames: ["b1.mydomain.example"]
    - ip: "$B2_IP"
      hostnames: ["b2.mydomain.example"]
  containers:
    - name: admin-client
      image: confluentinc/cp-server:7.9.0
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: tls-kafka-admin-p12
          mountPath: /mnt/adminssl
  volumes:
    - name: tls-kafka-admin-p12
      secret:
        secretName: tls-kafka-admin-p12
EOF

kubectl apply -f "$SCENARIO_HOME/admin-client.yaml"
kubectl wait pod/admin-client -n "$NS" --for=condition=Ready --timeout=60s

echo "Done. Exec into the pod with:"
echo "  kubectl -n $NS exec -it admin-client -- bash"
