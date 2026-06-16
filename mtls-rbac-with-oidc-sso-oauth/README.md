# Confluent For Kubernetes (CFK) – mTLS, RBAC, and SSO with Keycloak + Samba AD

> **DISCLAIMER:** Educational/lab use only. Not suitable for production.

Deploys Confluent Platform on Kubernetes with mTLS, OAuth/OIDC SSO (Keycloak + Samba AD), and Confluent RBAC (MDS). Extends the [official CFK example](https://github.com/confluentinc/confluent-kubernetes-examples/tree/master/security/mtls-rbac-with-sso-oauth) with:

- A second Kafka listener for mTLS-only admin access on port `9094`
- Samba AD as the identity backend, federated through Keycloak
- Control Center login validated with AD-backed users

## Prerequisites

- Ubuntu 22.04+
- `kubectl`, `helm`, `openssl`, `cfssl`, `docker`, `kind`, Java 17+

---

## Step 1 – Install dependencies

```bash
chmod 700 01-install-deps.sh
sudo ./01-install-deps.sh
```

After it completes, open a new shell or run `newgrp docker`. Do not stay inside a temporary `newgrp` subshell.

---

## Step 2 – Create the cluster

```bash
sudo usermod -aG docker $USER && newgrp docker
chmod 700 02-setup-cluster.sh
```

```bash
./02-setup-cluster.sh
```

Then export the working variables:

```bash
export SCENARIO_HOME=~/confluent-kubernetes-examples/security/mtls-rbac-with-sso-oauth
export CERT_HOME=$SCENARIO_HOME/../../assets/certs/component-certs
export ASSETS_HOME=$SCENARIO_HOME/../../assets/certs
```

If running on a VM:

```bash
export VM_IP=$(curl -s ifconfig.me)
export KEYCLOAK_HOST=${VM_IP}.sslip.io
export KEYCLOAK_BASE_URL=http://${KEYCLOAK_HOST}:8080
```

---

## Step 3 – Prepare the custom manifests (manual edits)

### 3.1 Keycloak custom manifest

```bash
cp $SCENARIO_HOME/keycloak.yaml $SCENARIO_HOME/keycloak-custom.yaml
vi $SCENARIO_HOME/keycloak-custom.yaml
```

Inside `realm.json → clients`, add after the `ssologin` client (around line 839):

```json
,
        {
        "id": "client-oauth",
        "clientId": "client-oauth",
        "name": "client-oauth",
        "enabled": true,
        "protocol": "openid-connect",
        "publicClient": false,
        "serviceAccountsEnabled": true,
        "clientAuthenticatorType": "client-secret",
        "secret": "client-oauth-secret",
        "standardFlowEnabled": false,
        "directAccessGrantsEnabled": false,
        "implicitFlowEnabled": false,
        "fullScopeAllowed": true,
        "protocolMappers": [
          {
            "name": "groups",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-group-membership-mapper",
            "consentRequired": false,
            "config": {
              "full.path": "true",
              "userinfo.token.claim": "true",
              "multivalued": "true",
              "id.token.claim": "true",
              "access.token.claim": "true",
              "claim.name": "groups"
            }
          }
        ]
        }
```

### 3.2 Confluent Platform custom manifest

```bash
cp $SCENARIO_HOME/confluent-platform.yaml $SCENARIO_HOME/confluent-platform-custom.yaml
vi $SCENARIO_HOME/confluent-platform-custom.yaml
```

Under `kind: Kafka → spec → listeners`, add at line 88:

```yaml
    custom:
      - name: custom-admin
        port: 9094
        authentication:
          type: mtls
          principalMappingRules:
            - RULE:.*CN[\s]?=[\s]?([a-zA-Z0-9.]*)?.*/$1/
        tls:
          enabled: true
```

Under `kind: Kafka → spec → listeners → external → authentication → oauthSettings`, add in line 75 (under tokenEndpointUri):

```yaml
        subClaimName: client_id
```

Under `kind: Kafka → spec`, add in line 53:

```yaml
  configOverrides:
    server:
      - listener.name.external.oauthbearer.sasl.server.callback.handler.class=io.confluent.kafka.server.plugins.auth.token.CompositeBearerValidatorCallbackHandler
      - listener.name.external.oauthbearer.sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required unsecuredLoginStringClaim_sub="thePrincipalName" publicKeyPath="/mnt/secrets/mds-token/mdsPublicKey.pem";
      - listener.name.external.principal.builder.class=io.confluent.kafka.security.authenticator.OAuthKafkaPrincipalBuilder
      - confluent.oauth.groups.claim.name=groups
      - confluent.metadata.server.user.store=OAUTH
      - confluent.metadata.server.oauthbearer.jwks.endpoint.url=http://keycloak:8080/realms/sso_test/protocol/openid-connect/certs
      - confluent.metadata.server.oauthbearer.expected.issuer=http://keycloak:8080/realms/sso_test
      - confluent.metadata.server.oauthbearer.sub.claim.name=client_id
      - confluent.metadata.server.oauthbearer.groups.claim.name=groups
```

Under `kind: KRaftController → spec`, add in line 12:

```yaml
  configOverrides:
    server:
      - listener.name.controller.principal.builder.class=io.confluent.kafka.security.authenticator.OAuthKafkaPrincipalBuilder
      - confluent.oauth.groups.claim.name=groups
```

If on a VM, replace `localhost` OIDC URLs:

```bash
sed -i "s|http://localhost:8080|$KEYCLOAK_BASE_URL|g" $SCENARIO_HOME/confluent-platform-custom.yaml
```

---

## Step 4 – Deploy Samba AD and create demo users

```bash
chmod 700 03-deploy-samba.sh
./03-deploy-samba.sh
```

Creates groups `g1`, `g2` and users `user-ad1` (→ g1), `user-ad2` (→ g2) in AD.

---

## Step 5 – Deploy CFK operator and Keycloak

```bash
chmod 700 04-deploy-keycloak.sh
./04-deploy-keycloak.sh
```

Default credentials: Keycloak admin UI `admin / admin`, preloaded test users `user1 / user1`, `user2 / user2`.

Port-forward Keycloak in a **separate terminal** (keep running for steps 6 and 7):

```bash
kubectl port-forward --address 0.0.0.0 svc/keycloak 8080:8080 -n confluent
```

---

## Step 6 – Federate Keycloak to Samba AD (manual UI step)

In the Keycloak Admin UI (`http://<VM_IP>:8080`, `admin/admin`), open realm `sso_test` → **User Federation** → Add LDAP provider:

| Field | Value |
|---|---|
| Vendor | Active Directory |
| Connection URL | `ldap://samba-ad-0.samba-ad.confluent.svc.cluster.local:389` |
| Bind type | simple |
| Bind DN | `CN=Administrator,CN=Users,DC=test,DC=local` |
| Bind credentials | `Password123!` |
| Edit Mode | READ_ONLY |
| Users DN | `CN=Users,DC=test,DC=local` |
| Username LDAP attribute | `sAMAccountName` |
| RDN LDAP attribute | `cn` |
| UUID LDAP attribute | `objectGUID` |
| User Object Classes | `person, organizationalPerson, user` |

Add a group mapper under **Mappers**:

| Field | Value |
|---|---|
| Name | `ad-groups` |
| Mapper Type | `group-ldap-mapper` |
| LDAP Groups DN | `CN=Users,DC=test,DC=local` |
| Group Name LDAP Attribute | `cn` |
| Group Object Classes | `group` |

Click **Synchronize all users**, then **Synchronize changed users**. Confirm `user-ad1` appears under group `/g1` in the Groups menu.

---

## Step 7 – Create the OAuth client group and assign the service account

Requires Keycloak port-forwarded on `localhost:8080`.

```bash
chmod 700 05-keycloak-sa-group.sh
./05-keycloak-sa-group.sh
```

Creates group `g-client-oauth` in Keycloak and adds `service-account-client-oauth` to it, so the `client-oauth` token includes `/g-client-oauth` in its groups claim and the RBAC rolebinding resolves correctly.

---

## Step 8 – Generate certificates and create Kubernetes secrets

```bash
chmod 700 06-generate-certs-secrets.sh
./06-generate-certs-secrets.sh
```

Creates: root CA, all component TLS certs, admin client cert + PKCS12, and the 9 required Kubernetes secrets:
`tls-kafka`, `tls-controlcenter`, `tls-schemaregistry`, `tls-connect`, `tls-kafkarestproxy`, `tls-kafka-admin-p12`, `oidccredential`, `oauth-jass`, `mds-token`

---

## Step 9 – Deploy Confluent Platform

```bash
chmod 700 07-deploy-platform.sh
./07-deploy-platform.sh
```

Deploys Confluent Platform, waits for Kafka to be ready, and applies two rolebindings:
- `controlcenter-rolebinding`: group `/g1` → ClusterAdmin (Control Center SSO)
- `client-oauth-clusteradmin`: group `/g-client-oauth` → ClusterAdmin (OAuth client)

---

## Step 10 – Validation

### 10.1 Control Center SSO

```bash
kubectl port-forward --address 0.0.0.0 controlcenter-0 9021:9021 -n confluent
```

Open `https://<VM_IP>:9021` and log in as `user-ad1 / user-ad1`.

### 10.2 OAuth + mTLS client (external listener, port 9092)

Recreate the admin-client pod with hostAliases (run once after Kafka is up):

```bash
chmod 700 08-recreate-admin-client.sh
./08-recreate-admin-client.sh
```

Exec into the pod:

```bash
kubectl -n confluent exec -it admin-client -- bash
```

Inside the pod:

```bash
mkdir -p ~/conf
cat > ~/conf/oauth.properties <<'EOF'
bootstrap.servers=kafka.mydomain.example:9092
security.protocol=SASL_SSL
sasl.mechanism=OAUTHBEARER
sasl.login.callback.handler.class=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler
sasl.jaas.config=org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required \
  clientId="client-oauth" clientSecret="client-oauth-secret" ;
sasl.oauthbearer.token.endpoint.url=http://keycloak:8080/realms/sso_test/protocol/openid-connect/token
ssl.keystore.location=/mnt/adminssl/kafka-admin-client.p12
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
ssl.keystore.type=PKCS12
ssl.truststore.location=/mnt/adminssl/truststore.p12
ssl.truststore.password=mystorepassword
ssl.truststore.type=PKCS12
ssl.endpoint.identification.algorithm=
EOF
```
```bash
kafka-topics \
  --bootstrap-server kafka.mydomain.example:9092 \
  --command-config ~/conf/oauth.properties \
  --create \
  --topic demo.oauth \
  --partitions 3 \
  --replication-factor 3
```

```bash
kafka-topics --bootstrap-server kafka.mydomain.example:9092 \
  --command-config ~/conf/oauth.properties --list
```

### 10.3 mTLS-only client (custom listener, port 9094)

Inside the admin-client pod:

```bash
cat > ~/conf/admin.properties <<'EOF'
bootstrap.servers=kafka.confluent.svc.cluster.local:9094
security.protocol=SSL
ssl.keystore.location=/mnt/adminssl/kafka-admin-client.p12
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
ssl.keystore.type=PKCS12
ssl.truststore.location=/mnt/adminssl/truststore.p12
ssl.truststore.password=mystorepassword
ssl.truststore.type=PKCS12
ssl.endpoint.identification.algorithm=
EOF
```
```bash
kafka-topics --bootstrap-server kafka.confluent.svc.cluster.local:9094 \
  --command-config ~/conf/admin.properties --list
```

## Sources

- [Security setup](https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/security/mtls-rbac-with-sso-oauth/README.md)
- [confluent-platform.yaml](https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/security/mtls-rbac-with-sso-oauth/confluent-platform.yaml)
- [controlcenter-rolebinding.yaml](https://github.com/confluentinc/confluent-kubernetes-examples/blob/master/security/control-center-sso/controlcenter-rolebinding.yaml)
- [Migrate from LDAP to OAuth RBAC in a RBAC-enabled Confluent Platform Cluster](https://docs.confluent.io/platform/current/security/authentication/oauth-oidc/configure-cs.html#optional-configuration-settings)
- [Configure Confluent Server Brokers for OAuth Authentication in Confluent Platform](https://docs.confluent.io/platform/current/security/authentication/oauth-oidc/configure-cs.html)
