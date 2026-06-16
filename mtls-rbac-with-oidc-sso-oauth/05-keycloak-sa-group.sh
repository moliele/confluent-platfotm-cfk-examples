#!/usr/bin/env bash
# Run as your normal user (NOT sudo).
# Requires: Keycloak port-forwarded on localhost:8080
# Run AFTER 04-deploy-keycloak.sh and AFTER the Keycloak UI federation (Step 6) is done.
set -euo pipefail

NS="${NS:-confluent}"
KCADM="kubectl exec -i -n $NS deploy/keycloak -- /opt/keycloak/bin/kcadm.sh"
REALM="sso_test"
KEYCLOAK_URL="http://localhost:8080"

echo "==> Logging into Keycloak admin CLI..."
$KCADM config credentials \
  --server http://localhost:8080 \
  --realm master \
  --user admin \
  --password admin

echo "==> Creating group g-client-oauth in realm $REALM..."
$KCADM create groups -r "$REALM" -s name=g-client-oauth

echo "==> Getting service account user ID via REST API..."
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -d 'grant_type=password' \
  -d 'client_id=admin-cli' \
  -d 'username=admin' \
  -d 'password=admin' \
  | grep -oP '"access_token"\s*:\s*"\K[^"]+')

SA_ID=$(curl -s \
  "$KEYCLOAK_URL/admin/realms/$REALM/clients/client-oauth/service-account-user" \
  -H "Authorization: Bearer $TOKEN" \
  | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)

GRP_ID=$(curl -s \
  "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
  -H "Authorization: Bearer $TOKEN" \
  | grep -oP '"id"\s*:\s*"\K[^"]+(?=[^}]*"name"\s*:\s*"g-client-oauth")' | head -1)

# Fallback: grep approach if above returns empty
if [ -z "$GRP_ID" ]; then
  GRP_ID=$(curl -s "$KEYCLOAK_URL/admin/realms/$REALM/groups" \
    -H "Authorization: Bearer $TOKEN" \
    | grep -B2 '"g-client-oauth"' | grep -oP '"id"\s*:\s*"\K[^"]+' | head -1)
fi

echo "SA_ID  : $SA_ID"
echo "GRP_ID : $GRP_ID"

if [ -z "$SA_ID" ] || [ -z "$GRP_ID" ]; then
  echo "ERROR: Could not resolve SA_ID or GRP_ID. Check Keycloak is port-forwarded and the realm import succeeded." >&2
  exit 1
fi

echo "==> Adding service account to group g-client-oauth..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  "$KEYCLOAK_URL/admin/realms/$REALM/users/$SA_ID/groups/$GRP_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{}")

echo "Response: $HTTP_CODE (expected 204)"

if [ "$HTTP_CODE" != "204" ]; then
  echo "ERROR: PUT returned $HTTP_CODE — group assignment may have failed." >&2
  exit 1
fi

echo "==> Verifying group membership..."
curl -s "$KEYCLOAK_URL/admin/realms/$REALM/users/$SA_ID/groups" \
  -H "Authorization: Bearer $TOKEN"

echo ""
echo "Done. service-account-client-oauth is now a member of /g-client-oauth."
