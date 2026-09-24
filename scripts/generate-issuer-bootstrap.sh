#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <issuer-host-or-host/path> [namespace]" >&2
  exit 1
fi

issuer_input="$1"
namespace="${2:-gxdch-issuer}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

did_private_key="$tmp_dir/did-ed25519-private.pem"
did_public_der="$tmp_dir/did-ed25519-public.der"
statuslist_key="$tmp_dir/statuslist-signing-key.pem"

openssl genpkey -algorithm ed25519 -out "$did_private_key" >/dev/null 2>&1
openssl pkey -in "$did_private_key" -pubout -outform DER -out "$did_public_der" >/dev/null 2>&1
openssl ecparam -name prime256v1 -genkey -noout -out "$statuslist_key" >/dev/null 2>&1

# The DID document must use the public key belonging to the issuer participant.
# The provisioning flow can replace this value after Identity API key creation.
did_x="${DID_PUBLIC_KEY_X:-$(tail -c 32 "$did_public_der" | basenc --base64url -w0)}"

issuer_host="${issuer_input%%/*}"
issuer_path=""
if [[ "$issuer_input" == */* ]]; then
  issuer_path="/${issuer_input#*/}"
  issuer_path="${issuer_path%/}"
fi

if [[ -z "$issuer_host" ]]; then
  echo "Issuer host must not be empty" >&2
  exit 1
fi

did_id="did:web:${issuer_host}"
did_doc_path="/did.json"
if [[ -n "$issuer_path" ]]; then
  IFS='/' read -r -a path_parts <<< "${issuer_path#/}"
  for part in "${path_parts[@]}"; do
    if [[ -n "$part" ]]; then
      did_id="${did_id}:${part}"
    fi
  done
fi

# Credential signing may use a separate key from the DID/authentication key.
# Publish it when its public x coordinate is supplied.
credential_method_json=""
credential_assertion_json=""
if [[ -n "${DID_CREDENTIAL_PUBLIC_KEY_X:-}" ]]; then
  credential_method_json=$(cat <<EOF
,
        {
          "id": "${did_id}#key-credential",
          "type": "JsonWebKey2020",
          "controller": "${did_id}",
          "publicKeyMultibase": null,
          "publicKeyJwk": {
            "kty": "OKP",
            "crv": "Ed25519",
            "kid": "key-credential",
            "x": "${DID_CREDENTIAL_PUBLIC_KEY_X}"
          }
        }
EOF
)
  credential_assertion_json=', "key-credential"'
fi

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
        location = ${did_doc_path} {
          alias /var/www/did.json;
          default_type application/json;
        }
      }
    }
  did.json: |
    {
      "service": [],
      "verificationMethod": [
        {
          "id": "${did_id}#key-1",
          "type": "JsonWebKey2020",
          "controller": "${did_id}",
          "publicKeyMultibase": null,
          "publicKeyJwk": {
            "kty": "OKP",
            "crv": "Ed25519",
            "x": "${did_x}"
          }
        }${credential_method_json}
      ],
      "authentication": [
        "key-1"
      ],
      "assertionMethod": [
        "key-1"${credential_assertion_json}
      ],
      "capabilityInvocation": [
        "key-1"
      ],
      "id": "${did_id}",
      "@context": [
        "https://www.w3.org/ns/did/v1",
        {
          "@base": "${did_id}"
        }
      ]
    }
EOF
