# Confluent For Kubernetes (CFK) - mTLS & LDAP RBAC Lab

### ⚠️ IMPORTANT: PRODUCTION DISCLAIMER
> **DISCLAIMER:** This repository and the configurations it contains are intended solely for educational and laboratory purposes. It is a simplified example designed to demonstrate the integration of mTLS and LDAP. It is not suitable for use in production environments. Before deploying it in a production environment, ensure you implement robust secret management, enterprise-grade Certificate Authority (CA) certificate rotation, and rigorous security hardening measures.

Translated with DeepL.com (free version)

---

## 🚀 Overview
This project demonstrates how to deploy the **Confluent Platform** on Kubernetes using **Confluent for Kubernetes (CFK)**, featuring:
* **Primary Auth (LDAP):** Centralized authentication via LDAP.
* **Secondary Auth (mTLS):** Admin access through a dedicated listener (port 9094).
* **Identity Mapping:** Granular authorization using `ConfluentRolebinding`.
* **KRaft Mode:** Modern Kafka architecture without Zookeeper dependency.

---

## 🛠️ Prerequisites
* **OS:** Ubuntu 22.04+ (or equivalent Linux distro)
* **Tools:** `kubectl`, `helm`, `openssl`, `cfssl`, `docker`, `kind`, `java`
* **Environment:** A Kubernetes cluster (Standard or `kind`)

---

## 🏗️ Step 1: Environment Setup

### 1. Install System Dependencies
```bash
sudo apt-get update
sudo apt-get upgrade -y

sudo apt install golang-cfssl

sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER && newgrp docker
```

```bash
# Install kubectl 
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"  
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl 

sudo apt install kubectx
```

```bash
# Install kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64  
chmod +x ./kind  
sudo mv ./kind /usr/local/bin/kind  
```

```bash
sudo apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release
 ```

```bash 
#install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
sudo ./get_helm.sh
```

```bash
#install java
sudo apt install openjdk-17-jre-headless
```

### 2. Local Cluster 
```bash
# Create kind cluster
kind create cluster --name confluent --wait 300s
kubectl cluster-info --context kind-confluent

kubectl create namespace confluent
kubens confluent
```

### 3. Clone Repository
```bash
git clone https://github.com/confluentinc/confluent-kubernetes-examples.git
```

---

## 🚀 Step 2: Deployment

### 1. Install Confluent Operator
```bash
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm upgrade --install operator confluentinc/confluent-for-kubernetes -n confluent

# Check if the operator is deployed
kubectl get pods -n confluent | grep operator
```

### 2. Deploy LDAP & Confluent Platform
```bash
export TUTORIAL_HOME=$PWD/confluent-kubernetes-examples
```

```bash
# Deploy OpenLDAP
helm upgrade --install -f $TUTORIAL_HOME/assets/openldap/ldaps-rbac.yaml test-ldap \
    $TUTORIAL_HOME/assets/openldap --namespace confluent
```

```bash
#Check that LDAP is deployed
kubectl get pods -n confluent
```

```bash
#(optional) Check the users
kubectl -n confluent exec -it ldap-0 -- bash
ldapsearch -LLL -x -H ldap://ldap.confluent.svc.cluster.local:389 -b 'dc=test,dc=com' -D "cn=mds,dc=test,dc=com" -w 'Developer!'

```

---

## 🔐 Step 3: Certificate Management (mTLS)

### 1. Generate Root CA and generate the CA certificate.
```bash
export TUTORIAL_HOME=$PWD/confluent-kubernetes-examples/assets/certs/component-certs
```

```bash
mkdir -p $TUTORIAL_HOME/generated
```

```bash
openssl genrsa -out $TUTORIAL_HOME/generated/rootCAkey.pem 2048
openssl req -x509  -new -nodes \
  -key $TUTORIAL_HOME/generated/rootCAkey.pem \
  -days 3650 \
  -out $TUTORIAL_HOME/generated/cacerts.pem \
  -subj "/C=US/ST=CA/L=MVT/O=TestOrg/OU=Cloud/CN=TestCA"
```

```bash    
#Check the validity of the CA
openssl x509 -in $TUTORIAL_HOME/generated/cacerts.pem -text -noout
```

### 2. Generate  Confluent component server certificates
Example for Kafka Server (repeat for Connect, Schema Registry, etc.):
```bash
# Create Zookeeper server certificates
# Use the SANs listed in zookeeper-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/zookeeper-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/zookeeper-server

# Create Kafka server certificates
# Use the SANs listed in kafka-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/kafka-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/kafka-server

# Create Kraft server certificates
# Use the SANs listed in kraft-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/kraft-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/kraft-server

# Create ControlCenter server certificates
# Use the SANs listed in controlcenter-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/controlcenter-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/controlcenter-server

# Create SchemaRegistry server certificates
# Use the SANs listed in schemaregistry-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/schemaregistry-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/schemaregistry-server

# Create Connect server certificates
# Use the SANs listed in connect-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/connect-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/connect-server

# Create ksqlDB server certificates
# Use the SANs listed in ksqldb-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/ksqldb-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/ksqldb-server

# Create Kafka Rest Proxy server certificates
# Use the SANs listed in kafkarestproxy-server-domain.json

cfssl gencert -ca=$TUTORIAL_HOME/generated/cacerts.pem \
-ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
-config=$TUTORIAL_HOME/ca-config.json \
-profile=server $TUTORIAL_HOME/kafkarestproxy-server-domain.json | cfssljson -bare $TUTORIAL_HOME/generated/kafkarestproxy-server

# Check validity of server certificates
openssl x509 -in $TUTORIAL_HOME/generated/zookeeper-server.pem -text -noout

openssl x509 -in $TUTORIAL_HOME/generated/kafka-server.pem -text -noout

openssl x509 -in $TUTORIAL_HOME/generated/controlcenter-server.pem -text -noout

openssl x509 -in $TUTORIAL_HOME/generated/schemaregistry-server.pem -text -noout

openssl x509 -in $TUTORIAL_HOME/generated/connect-server.pem -text -noout

openssl x509 -in $TUTORIAL_HOME/generated/ksqldb-server.pem -text -noout

openssl x509 -in $TUTORIAL_HOME/generated/kafkarestproxy-server.pem -text -noout
```

### 3. Generate Admin Client Certificate
```bash
cat > $TUTORIAL_HOME/kafka-admin-client-domain.json << 'EOF'
{
  "CN": "kafka.admin.local",
  "hosts": [
    "kafka.admin.local",
    "localhost"
  ],
  "key": { "algo": "rsa", "size": 2048 },
  "names": [
    {
      "C": "Universe",
      "ST": "Pangea",
      "L": "Earth"
    }
  ]
}
EOF

cfssl gencert \
  -ca=$TUTORIAL_HOME/generated/cacerts.pem \
  -ca-key=$TUTORIAL_HOME/generated/rootCAkey.pem \
  -config=$TUTORIAL_HOME/ca-config.json \
  -profile=client \
  $TUTORIAL_HOME/kafka-admin-client-domain.json | \
  cfssljson -bare $TUTORIAL_HOME/generated/kafka-admin-client
```


### 4. Create cert and secret for admin client (java)
```bash
cd $TUTORIAL_HOME/generated
```

```bash
openssl pkcs12 -export \
  -in  kafka-admin-client.pem \
  -inkey kafka-admin-client-key.pem \
  -out kafka-admin-client.p12 \
  -name kafka-admin-local \
  -password pass:mystorepassword

keytool -importcert \
  -trustcacerts \
  -file cacerts.pem \
  -alias testca \
  -keystore truststore.p12 \
  -storetype PKCS12 \
  -storepass mystorepassword \
  -noprompt

kubectl -n confluent create secret generic tls-kafka-admin-p12 \
  --from-file=kafka-admin-client.p12=kafka-admin-client.p12 \
  --from-file=truststore.p12=truststore.p12
```

```bash  
openssl pkcs12 -in truststore.p12 -nokeys -passin pass:mystorepassword
```

### 5. Deploy TLS Secrets to Kubernetes

## 1. Secrets for Confluent components
```bash
kubectl create secret generic tls-kafka \
  --from-file=fullchain.pem=$TUTORIAL_HOME/generated/kafka-server.pem \
  --from-file=cacerts.pem=$TUTORIAL_HOME/generated/cacerts.pem \
  --from-file=privkey.pem=$TUTORIAL_HOME/generated/kafka-server-key.pem \
  --namespace confluent

kubectl create secret generic tls-controlcenter \
  --from-file=fullchain.pem=$TUTORIAL_HOME/generated/controlcenter-server.pem \
  --from-file=cacerts.pem=$TUTORIAL_HOME/generated/cacerts.pem \
  --from-file=privkey.pem=$TUTORIAL_HOME/generated/controlcenter-server-key.pem \
  --namespace confluent

kubectl create secret generic tls-schemaregistry \
  --from-file=fullchain.pem=$TUTORIAL_HOME/generated/schemaregistry-server.pem \
  --from-file=cacerts.pem=$TUTORIAL_HOME/generated/cacerts.pem \
  --from-file=privkey.pem=$TUTORIAL_HOME/generated/schemaregistry-server-key.pem \
  --namespace confluent

kubectl create secret generic tls-connect \
  --from-file=fullchain.pem=$TUTORIAL_HOME/generated/connect-server.pem \
  --from-file=cacerts.pem=$TUTORIAL_HOME/generated/cacerts.pem \
  --from-file=privkey.pem=$TUTORIAL_HOME/generated/connect-server-key.pem \
  --namespace confluent
  
kubectl create secret generic tls-kafkarestproxy \
  --from-file=fullchain.pem=$TUTORIAL_HOME/generated/kafkarestproxy-server.pem \
  --from-file=cacerts.pem=$TUTORIAL_HOME/generated/cacerts.pem \
  --from-file=privkey.pem=$TUTORIAL_HOME/generated/kafkarestproxy-server-key.pem \
  --namespace confluent

kubectl create secret generic tls-kafka-admin-client \
  --from-file=fullchain.pem=$TUTORIAL_HOME/generated/kafka-admin-client.pem \
  --from-file=cacerts.pem=$TUTORIAL_HOME/generated/cacerts.pem \
  --from-file=privkey.pem=$TUTORIAL_HOME/generated/kafka-admin-client-key.pem \
  --namespace confluent
```
## 6. Secrets for clients
```bash
cd  ~
```

```bash
export TUTORIAL_HOME=$PWD/confluent-kubernetes-examples/migration/nonRBACToRBAC/mtlsLdap
```

```bash
kubectl create secret generic credential \
--from-file=ldap.txt=$TUTORIAL_HOME/ldap.txt \
-n confluent

kubectl create secret generic mds-token \
--from-file=mdsPublicKey.pem=$TUTORIAL_HOME/../../../assets/certs/mds-publickey.txt \
--from-file=mdsTokenKeyPair.pem=$TUTORIAL_HOME/../../../assets/certs/mds-tokenkeypair.txt \
-n confluent

kubectl create secret generic mds-client \
--from-file=bearer.txt=$TUTORIAL_HOME/bearer.txt \
-n confluent

kubectl create secret generic c3-mds-client \
--from-file=bearer.txt=$TUTORIAL_HOME/c3-client.txt \
-n confluent

kubectl create secret generic connect-mds-client \
--from-file=bearer.txt=$TUTORIAL_HOME/connect-client.txt \
-n confluent

kubectl create secret generic sr-mds-client \
--from-file=bearer.txt=$TUTORIAL_HOME/sr-client.txt \
-n confluent

kubectl create secret generic krp-mds-client \
--from-file=bearer.txt=$TUTORIAL_HOME/krp-client.txt \
-n confluent


kubectl create secret generic rest-credential \
--from-file=bearer.txt=$TUTORIAL_HOME/bearer.txt \
--from-file=basic.txt=$TUTORIAL_HOME/bearer.txt \
-n confluent

#check the secreats created
```

---

## 👮 Step 5: Confluent platform deployment

In `confluent-platform.yaml`, the `principalMappingRules` extract the identity directly from the certificate:

```yaml

principalMappingRules:

  - RULE:.*CN[\\s]?=[\\s]?([a-zA-Z0-9.]*)?.*/$1/

```
- 
### 1. Create CRs
```bash
vi confluent-platform.yaml
```

```bash
apiVersion: platform.confluent.io/v1beta1
kind: KRaftController
metadata:
  name: kraftcontroller
  namespace: confluent
spec:
  configOverrides:
    server:
      # add missing replication listener configs in kraft. Known CFK bug, to be fixed in future release
      - listener.name.replication.ssl.key.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - listener.name.replication.ssl.keystore.location=/mnt/sslcerts/keystore.p12
      - listener.name.replication.ssl.keystore.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - listener.name.replication.ssl.truststore.location=/mnt/sslcerts/truststore.p12
      - listener.name.replication.ssl.truststore.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - listener.security.protocol.map=CONTROLLER:SSL,REPLICATION:SSL
      - confluent.security.event.logger.enable=false
      #mTLS para clientes internos
      - confluent.metadata.ssl.keystore.location=/mnt/sslcerts/keystore.p12
      - confluent.metadata.ssl.keystore.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - confluent.metadata.ssl.key.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - confluent.metadata.ssl.truststore.location=/mnt/sslcerts/truststore.p12
      - confluent.metadata.ssl.truststore.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - confluent.metadata.ssl.keystore.type=PKCS12
      - confluent.metadata.ssl.truststore.type=PKCS12
  dataVolumeCapacity: 10Gi
  image:
    application: confluentinc/cp-server:7.9.0
    init: confluentinc/confluent-init-container:2.11.0
  listeners:
    controller:
      authentication:
        type: mtls
        principalMappingRules:
          - RULE:.*CN=([a-zA-Z0-9.-]*).*$/$1/
      tls:
        enabled: true
  authorization:
    superUsers:
      - User:kafka
    type: rbac
  dependencies:
    mdsKafkaCluster:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9071
      authentication:
        type: mtls
      tls:
        enabled: true
  tls:
    secretRef: tls-kafka
  replicas: 3
---
apiVersion: platform.confluent.io/v1beta1
kind: Kafka
metadata:
  name: kafka
  namespace: confluent
spec:
  replicas: 3
  image:
    application: confluentinc/cp-server:7.9.0
    init: confluentinc/confluent-init-container:2.11.0
  dataVolumeCapacity: 10Gi
  tls:
    secretRef: tls-kafka
  configOverrides:
    server:
      - confluent.security.event.logger.enable=false
      - confluent.metadata.ssl.keystore.location=/mnt/sslcerts/keystore.p12
      - confluent.metadata.ssl.keystore.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - confluent.metadata.ssl.key.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - confluent.metadata.ssl.truststore.location=/mnt/sslcerts/truststore.p12
      - confluent.metadata.ssl.truststore.password=${file:/mnt/sslcerts/jksPassword.txt:jksPassword}
      - confluent.metadata.ssl.keystore.type=PKCS12
      - confluent.metadata.ssl.truststore.type=PKCS12
  authorization:
    superUsers:
      - User:kafka
    type: rbac
  services:
    mds:
      tls:
        enabled: true
      tokenKeyPair:
        secretRef: mds-token
      externalAccess:
        type: loadBalancer
        loadBalancer:
          domain: my.domain
          prefix: rb-mds
      provider:
        ldap:
          address: ldap://ldap.confluent.svc.cluster.local:389
          authentication:
            type: simple
            simple:
              secretRef: credential
          configurations:
            groupNameAttribute: cn
            groupObjectClass: group
            groupMemberAttribute: member
            groupMemberAttributePattern: CN=(.*),DC=test,DC=com
            groupSearchBase: dc=test,dc=com
            groupSearchScope: 1
            userNameAttribute: cn
            userMemberOfAttributePattern: CN=(.*),DC=test,DC=com
            userObjectClass: organizationalRole
            userSearchBase: dc=test,dc=com
            userSearchScope: 1
  listeners:
    internal:
      authentication:
        type: mtls
        principalMappingRules:
          - RULE:.*CN[\\s]?=[\\s]?([a-zA-Z0-9.]*)?.*/$1/
      tls:
        enabled: true
    custom:
      - name: custom-admin
        port: 9094
        authentication:
          type: mtls
          principalMappingRules:
            - RULE:.*CN[\s]?=[\s]?([a-zA-Z0-9.]*)?.*/$1/
        tls:
          enabled: true
    external:
      authentication:
        type: mtls
        principalMappingRules:
          - RULE:.*CN[\\s]?=[\\s]?([a-zA-Z0-9.]*)?.*/$1/
      tls:
        enabled: true
      externalAccess:
        type: loadBalancer
        loadBalancer:
          domain: mydomain.example
          brokerPrefix: b
          bootstrapPrefix: kafka
  dependencies:
    kafkaRest:
      authentication:
        type: bearer
        bearer:
          secretRef: mds-client
    kRaftController:
      controllerListener:
        tls:
          enabled: true
        authentication:
          type: mtls
      clusterRef:
        name: kraftcontroller
---
apiVersion: platform.confluent.io/v1beta1
kind: Connect
metadata:
  name: connect
  namespace: confluent
spec:
  replicas: 2
  image:
    application: confluentinc/cp-server-connect:7.9.0
    init: confluentinc/confluent-init-container:2.11.0
  authorization:
    type: rbac
  tls:
    secretRef: tls-connect
  authentication:
    type: mtls
  externalAccess:
    type: loadBalancer
    loadBalancer:
      domain: mydomain.example
      prefix: connect
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9071
      authentication:
        type: mtls
      tls:
        enabled: true
    mds:
      endpoint: https://kafka.confluent.svc.cluster.local:8090
      tokenKeyPair:
        secretRef: mds-token
      authentication:
        type: bearer
        bearer:
          secretRef: connect-mds-client
      tls:
        enabled: true
---
apiVersion: platform.confluent.io/v1beta1
kind: SchemaRegistry
metadata:
  name: schemaregistry
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-schema-registry:7.9.0
    init: confluentinc/confluent-init-container:2.11.0
  authorization:
    type: rbac
  tls:
    secretRef: tls-schemaregistry
  authentication:
    type: mtls
  externalAccess:
    type: loadBalancer
    loadBalancer:
      domain: mydomain.example
      prefix: schemaregistry
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9071
      authentication:
        type: mtls
      tls:
        enabled: true
    mds:
      endpoint: https://kafka.confluent.svc.cluster.local:8090
      tokenKeyPair:
        secretRef: mds-token
      authentication:
        type: bearer
        bearer:
          secretRef: sr-mds-client
      tls:
        enabled: true
---
apiVersion: platform.confluent.io/v1beta1
kind: KafkaRestProxy
metadata:
  name: kafkarestproxy
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-kafka-rest:7.9.0
    init: confluentinc/confluent-init-container:2.11.0
  authorization:
    type: rbac
  tls:
    secretRef: tls-kafkarestproxy
  authentication:
    type: mtls
  externalAccess:
    type: loadBalancer
    loadBalancer:
      domain: mydomain.example
      prefix: kafkarestproxy
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9071
      authentication:
        type: mtls
      tls:
        enabled: true
    schemaRegistry:
      url: https://schemaregistry.confluent.svc.cluster.local:8081
      authentication:
        type: mtls
      tls:
        enabled: true
    mds:
      endpoint: https://kafka.confluent.svc.cluster.local:8090
      tokenKeyPair:
        secretRef: mds-token
      authentication:
        type: bearer
        bearer:
          secretRef: krp-mds-client
      tls:
        enabled: true
---
apiVersion: platform.confluent.io/v1beta1
kind: ControlCenter
metadata:
  name: controlcenter
  namespace: confluent
spec:
  replicas: 1
  image:
    application: confluentinc/cp-enterprise-control-center:7.9.0
    init: confluentinc/confluent-init-container:2.11.0
  authorization:
    type: rbac
  dataVolumeCapacity: 10Gi
  externalAccess:
    type: loadBalancer
    loadBalancer:
      domain: mydomain.example
      prefix: controlcenter
  tls:
    secretRef: tls-controlcenter
  dependencies:
    kafka:
      bootstrapEndpoint: kafka.confluent.svc.cluster.local:9071
      authentication:
        type: mtls
      tls:
        enabled: true
    connect:
      - name: connect
        url:  https://connect.confluent.svc.cluster.local:8083
        authentication:
          type: mtls
        tls:
          enabled: true
    mds:
      endpoint: https://kafka.confluent.svc.cluster.local:8090
      tokenKeyPair:
        secretRef: mds-token
      authentication:
        type: bearer
        bearer:
          secretRef: c3-mds-client
      tls:
        enabled: true
    schemaRegistry:
      url: https://schemaregistry.confluent.svc.cluster.local:8081
      authentication:
        type: mtls
      tls:
        enabled: true
---
apiVersion: platform.confluent.io/v1beta1
kind: KafkaRestClass
metadata:
  name: default
  namespace: confluent
spec:
  kafkaRest:
    authentication:
      type: bearer
      bearer:
        secretRef: rest-credential
---
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
```

```bash      
#deploy it
kubectl apply -f confluent-platform.yaml -n confluent
```

```bash
kubectl get pods -w -n confluent
```
---

## 👮 Step 6: Authorization (RBAC & ACLs)

### 1. Kafka ACLs
Grant permissions to internal components via a broker exec:
```bash
kubectl -n confluent exec -it kafka-0 -- bash
```

```bash
cat <<-EOF > /opt/confluentinc/kafka.properties
bootstrap.servers=kafka.confluent.svc.cluster.local:9071
security.protocol=SSL
ssl.keystore.location=/mnt/sslcerts/keystore.p12
ssl.keystore.password=mystorepassword
ssl.truststore.location=/mnt/sslcerts/truststore.p12
ssl.truststore.password=mystorepassword
EOF
```

```bash

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add  --allow-principal "User:sr" --allow-principal "User:connect" \
--allow-principal "User:c3" --allow-principal "User:krp" \
--operation All --topic "*"

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:sr" \
--operation Read \
--group id_schemaregistry_confluent

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:connect" \
--operation Read \
--group confluent.connect

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:c3" \
--operation Describe --operation Delete --operation Read \
--group ConfluentTelemetryReporterSampler \
--resource-pattern-type prefixed

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:c3" \
--operation All \
--group _confluent-controlcenter \
--resource-pattern-type prefixed

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:sr" \
--allow-principal "User:connect" \
--allow-principal "User:c3" \
--operation ClusterAction \
--cluster kafka-cluster

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:connect" \
--allow-principal "User:c3" \
--operation Create \
--cluster kafka-cluster

/bin/kafka-acls --bootstrap-server kafka.confluent.svc.cluster.local:9071 \
--command-config /opt/confluentinc/kafka.properties \
--add \
--allow-principal "User:c3" \
--operation Describe --operation AlterConfigs  --operation DescribeConfigs \
--cluster kafka-cluster
```
```bash
exit
```

### 2. Confluent Rolebindings
```bash
KAFKA_CLUSTER_ID=$(kubectl get kafka kafka -n confluent -o jsonpath='{.status.clusterID}')
echo $KAFKA_CLUSTER_ID
```
```bash
#create the cr
vi $TUTORIAL_HOME/kafka-admin-local-rolebinding.yaml
```
```bash
apiVersion: platform.confluent.io/v1beta1
kind: ConfluentRolebinding
metadata:
  name: kafka-admin-local-clusteradmin
  namespace: confluent
spec:
  principal:
    type: user
    name: kafka.admin.local
  role: ClusterAdmin
  clustersScopeByIds:
    kafkaClusterId: <REPLACE WITH THE KAFKA_CLUSTER_ID>
```

```bash
# Apply the Rolebinding for the admin user
kubectl apply -f $TUTORIAL_HOME/kafka-admin-local-rolebinding.yaml
```

---

## 🧪 Step 7: Validation

### 1. Test mTLS Admin Client
```bash
kubectl -n confluent exec -it admin-client -- bash
```

```bash
mkdir -p ~/conf

cat > ~/conf/admin.properties << 'EOF'
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
# List topics using mTLS .p12 Keystore
kafka-topics --bootstrap-server kafka.confluent.svc.cluster.local:9094 \
    --command-config ~/conf/admin.properties --list
```

```bash
kafka-topics \
--bootstrap-server kafka.confluent.svc.cluster.local:9094 \
--command-config ~/conf/admin.properties \
--create --topic demo.clusteradmin \
--partitions 3 --replication-factor 3
```

```bash
kafka-configs \
  --bootstrap-server kafka.confluent.svc.cluster.local:9094 \
  --command-config ~/conf/admin.properties \
  --entity-type topics --entity-name demo.clusteradmin \
  --describe
```

### 2. (Optional) Control Center Access
```bash
kubectl port-forward controlcenter-0 9021:9021 -n confluent
```
Access via: `https://localhost:9021`
