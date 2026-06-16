#!/usr/bin/env bash
# Run as your normal user (NOT sudo) — kubectl/helm must run as you, not root.
set -euo pipefail

SCENARIO_HOME="${SCENARIO_HOME:-$HOME/confluent-kubernetes-examples/security/mtls-rbac-with-sso-oauth}"
CERT_HOME="${CERT_HOME:-$SCENARIO_HOME/../../assets/certs/component-certs}"
ASSETS_HOME="${ASSETS_HOME:-$SCENARIO_HOME/../../assets/certs}"

NS=confluent
GEN="$CERT_HOME/generated"
mkdir -p "$GEN"

# ── Root CA ────────────────────────────────────────────────────────────────────
echo "==> Generating root CA..."
openssl genrsa -out "$GEN/rootCAkey.pem" 2048
openssl req -x509 -new -nodes \
  -key "$GEN/rootCAkey.pem" \
  -days 3650 \
  -out "$GEN/cacerts.pem" \
  -subj "/C=US/ST=CA/L=MVT/O=TestOrg/OU=Cloud/CN=TestCA"

# ── Component server certs ─────────────────────────────────────────────────────
echo "==> Generating component server certificates..."
for component in kafka kraft controlcenter schemaregistry connect kafkarestproxy; do
  cfssl gencert \
    -ca="$GEN/cacerts.pem" \
    -ca-key="$GEN/rootCAkey.pem" \
    -config="$CERT_HOME/ca-config.json" \
    -profile=server \
    "$CERT_HOME/${component}-server-domain.json" | cfssljson -bare "$GEN/${component}-server"
done

# ── Admin client cert ──────────────────────────────────────────────────────────
echo "==> Generating admin client certificate..."
cat > "$CERT_HOME/kafka-admin-client-domain.json" << 'CSREOF'
{
  "CN": "kafka.admin.local",
  "hosts": ["kafka.admin.local", "localhost"],
  "key": { "algo": "rsa", "size": 2048 },
  "names": [{ "C": "US", "ST": "CA", "L": "MVT", "O": "TestOrg", "OU": "Cloud" }]
}
CSREOF

cfssl gencert \
  -ca="$GEN/cacerts.pem" \
  -ca-key="$GEN/rootCAkey.pem" \
  -config="$ASSETS_HOME/ca-config.json" \
  -profile=client \
  "$CERT_HOME/kafka-admin-client-domain.json" | cfssljson -bare "$GEN/kafka-admin-client"

# ── PKCS12 keystore + truststore ───────────────────────────────────────────────
echo "==> Creating PKCS12 keystore and truststore..."
openssl pkcs12 -export \
  -in "$GEN/kafka-admin-client.pem" \
  -inkey "$GEN/kafka-admin-client-key.pem" \
  -out "$GEN/kafka-admin-client.p12" \
  -name kafka-admin-local \
  -password pass:mystorepassword

keytool -importcert \
  -trustcacerts \
  -file "$GEN/cacerts.pem" \
  -alias testca \
  -keystore "$GEN/truststore.p12" \
  -storetype PKCS12 \
  -storepass mystorepassword \
  -noprompt

# ── Kubernetes TLS Secrets ─────────────────────────────────────────────────────
echo "==> Creating Kubernetes TLS secrets..."
for component in controlcenter schemaregistry connect kafkarestproxy; do
  kubectl create secret generic "tls-${component}" \
    --from-file="fullchain.pem=$GEN/${component}-server.pem" \
    --from-file="cacerts.pem=$GEN/cacerts.pem" \
    --from-file="privkey.pem=$GEN/${component}-server-key.pem" \
    -n "$NS"
done

kubectl create secret generic tls-kafka \
  --from-file="fullchain.pem=$GEN/kafka-server.pem" \
  --from-file="cacerts.pem=$GEN/cacerts.pem" \
  --from-file="privkey.pem=$GEN/kafka-server-key.pem" \
  -n "$NS"

kubectl create secret generic tls-kafka-admin-p12 \
  --from-file="kafka-admin-client.p12=$GEN/kafka-admin-client.p12" \
  --from-file="truststore.p12=$GEN/truststore.p12" \
  -n "$NS"

kubectl create secret generic oidccredential \
  --from-file="oidcClientSecret.txt=$SCENARIO_HOME/oidcClientSecret.txt" \
  -n "$NS"

kubectl create secret generic oauth-jass \
  --from-file="oauth.txt=$SCENARIO_HOME/oidcClientSecret.txt" \
  -n "$NS"

kubectl create secret generic mds-token \
  --from-file="mdsPublicKey.pem=$ASSETS_HOME/mds-publickey.txt" \
  --from-file="mdsTokenKeyPair.pem=$ASSETS_HOME/mds-tokenkeypair.txt" \
  -n "$NS"

echo "==> Creating admin-client pod..."
cat << 'EOF' > "$SCENARIO_HOME/admin-client.yaml"
apiVersion: v1
kind: Pod
metadata:
  name: admin-client
  namespace: confluent
spec:
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

echo "Done. All secrets created:"
kubectl get secret -n "$NS" | grep -E 'tls-|oidc|oauth|mds'
