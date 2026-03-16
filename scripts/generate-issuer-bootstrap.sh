#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <issuer-hostname> [namespace]" >&2
  exit 1
fi

issuer_host="$1"
namespace="${2:-gxdch-issuer}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

did_private_key="$tmp_dir/did-ed25519-private.pem"
did_public_der="$tmp_dir/did-ed25519-public.der"
statuslist_key="$tmp_dir/statuslist-signing-key.pem"

openssl genpkey -algorithm ed25519 -out "$did_private_key" >/dev/null 2>&1
openssl pkey -in "$did_private_key" -pubout -outform DER -out "$did_public_der" >/dev/null 2>&1
openssl ecparam -name prime256v1 -genkey -noout -out "$statuslist_key" >/dev/null 2>&1

did_x="$(tail -c 32 "$did_public_der" | basenc --base64url -w0)"

cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: issuer-bootstrap
  namespace: ${namespace}
type: Opaque
stringData:
  statuslist-signing-key.pem: |
$(sed 's/^/    /' "$statuslist_key")
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: dataspace-issuer-did-config
  namespace: ${namespace}
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 80;
        location = /.well-known/did.json {
          root /var/www;
          default_type application/json;
        }
      }
    }
  did.json: |
    {
      "service": [],
      "verificationMethod": [
        {
          "id": "did:web:${issuer_host}#key-1",
          "type": "JsonWebKey2020",
          "controller": "did:web:${issuer_host}",
          "publicKeyMultibase": null,
          "publicKeyJwk": {
            "kty": "OKP",
            "crv": "Ed25519",
            "x": "${did_x}"
          }
        }
      ],
      "authentication": [
        "key-1"
      ],
      "id": "did:web:${issuer_host}",
      "@context": [
        "https://www.w3.org/ns/did/v1",
        {
          "@base": "did:web:${issuer_host}"
        }
      ]
    }
EOF
