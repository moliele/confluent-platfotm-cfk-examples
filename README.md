# confluent-platfotm-cfk-examples

Confluent Platform examples for Confluent for Kubernetes (CFK).

> **DISCLAIMER:** Educational/lab use only. Not suitable for production.

## Repository structure

Each folder in this repository should represent a self-contained example.

```text
.
├── mtls-ldap-rbac/
├── mtls-rbac-with-oidc-sso-oauth/
└── ...
```

## How to use this repository

### 1. Clone the repository

```bash
git clone https://github.com/moliele/confluent-platfotm-cfk-examples.git
cd confluent-platfotm-cfk-examples
```

### 2. Choose an example

Browse the available folders and select the scenario you want to deploy.

### 3. Read the example README

Each example should include its own `README.md` with:

* prerequisites
* environment assumptions
* deployment steps
* validation steps
* cleanup steps

### 4. Deploy the example

Apply the manifests according to the instructions in the selected example.
