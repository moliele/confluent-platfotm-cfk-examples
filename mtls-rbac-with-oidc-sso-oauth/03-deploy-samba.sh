#!/usr/bin/env bash
# Run as your normal user (NOT sudo)
set -euo pipefail

NS="${NS:-confluent}"
MANIFEST="${MANIFEST:-/tmp/ad-samba.yaml}"
POD="samba-ad-0"

echo "==> Creating Samba AD manifest at $MANIFEST ..."
cat > "$MANIFEST" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: samba-ad
  namespace: confluent
spec:
  clusterIP: None
  selector:
    app: samba-ad
  ports:
    - { name: ldap,   port: 389,  targetPort: 389  }
    - { name: ldaps,  port: 636,  targetPort: 636  }
    - { name: gc,     port: 3268, targetPort: 3268 }
    - { name: gc-ssl, port: 3269, targetPort: 3269 }
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: samba-ad
  namespace: confluent
spec:
  serviceName: samba-ad
  replicas: 1
  selector:
    matchLabels:
      app: samba-ad
  template:
    metadata:
      labels:
        app: samba-ad
    spec:
      hostname: samba-ad-0
      subdomain: samba-ad
      containers:
        - name: samba-ad
          image: linuxcrafts/samba-ad-dc:latest
          securityContext:
            privileged: true
          env:
            - { name: DNS_DOMAIN,      value: test.local      }
            - { name: WORKGROUP,       value: TEST            }
            - { name: NETBIOS_NAME,    value: SAMBAAD0        }
            - { name: DNS_BACKEND,     value: SAMBA_INTERNAL  }
            - { name: FUNCTION_LEVEL,  value: 2008_R2         }
            - { name: ROLE,            value: dc              }
            - { name: ADMIN_PASSWORD,  value: Password123!    }
            - { name: DNS_FORWARDER,   value: 8.8.8.8         }
          ports:
            - { containerPort: 389  }
            - { containerPort: 636  }
            - { containerPort: 3268 }
            - { containerPort: 3269 }
EOF

echo "==> Applying manifest..."
kubectl apply -f "$MANIFEST" -n "$NS"

echo "==> Waiting for pod to be Ready..."
kubectl wait pod/"$POD" -n "$NS" --for=condition=Ready --timeout=180s

echo "==> Waiting for Samba AD provisioning to finish..."
until kubectl exec -n "$NS" "$POD" -- samba-tool domain level show --configfile=/samba/etc/smb.conf >/dev/null 2>&1; do
  echo "   Samba AD not ready yet, waiting 10s..."
  sleep 10
done

echo "==> Creating AD groups..."
kubectl exec -n "$NS" "$POD" -- samba-tool group add g1 --configfile=/samba/etc/smb.conf
kubectl exec -n "$NS" "$POD" -- samba-tool group add g2 --configfile=/samba/etc/smb.conf

echo "==> Creating AD users..."
kubectl exec -n "$NS" "$POD" -- samba-tool user create user-ad1 user-ad1 --configfile=/samba/etc/smb.conf
kubectl exec -n "$NS" "$POD" -- samba-tool user create user-ad2 user-ad2 --configfile=/samba/etc/smb.conf

echo "==> Adding users to groups..."
kubectl exec -n "$NS" "$POD" -- samba-tool group addmembers g1 user-ad1 --configfile=/samba/etc/smb.conf
kubectl exec -n "$NS" "$POD" -- samba-tool group addmembers g2 user-ad2 --configfile=/samba/etc/smb.conf

echo "==> Validation..."
kubectl exec -n "$NS" "$POD" -- samba-tool user show user-ad1 --configfile=/samba/etc/smb.conf
kubectl exec -n "$NS" "$POD" -- samba-tool group listmembers g1 --configfile=/samba/etc/smb.conf

echo "==> Done."
