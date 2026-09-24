# GXDCH-Issuer

This repository is a GitOps-ready ArgoCD project for deploying a minimal dataspace issuer stack into Kubernetes.

It is based on the issuer-side components used by the Eclipse EDC Minimum Viable Dataspace demo:

- dataspace issuer service
- PostgreSQL backing database
- HashiCorp Vault for issuer secrets
- static `did:web` hosting through NGINX

This repo does not include participant-side EDC runtimes or Identity Hubs. It is intended for the `gxdch` cluster as the central issuer side.

## Scope

This stack is focused on the issuer components that should live centrally in `gxdch`:

- `dataspace-issuer-service`
- `dataspace-issuer` DID server
- `issuer-postgres`
- `issuer-vault`

It does not deploy the Gaia-X `oid4vc-poc-backend` by default. That backend is a broader PoC for issuer/verifier/wallet flows and is better treated as an optional follow-up.

## Repository Layout

```text
platform-apps/
  argocd/
    gxdch-issuer-application.yaml
  gxdch-issuer/
    appproject.yaml
    gxdch-issuer-core-application.yaml
    kustomization.yaml
    namespace.yaml
    core/
      ...
scripts/
  build-mvd-issuer-image.sh
  generate-issuer-bootstrap.sh
```

## Repository URL

The manifests currently point to:

```text
https://github.com/Data-Space-Core/GXDCH-Issuer.git
```

If your repository URL differs, update:

- `platform-apps/argocd/gxdch-issuer-application.yaml`
- `platform-apps/gxdch-issuer/appproject.yaml`
- `platform-apps/gxdch-issuer/gxdch-issuer-core-application.yaml`

## Important Prerequisites

### 1. Build and publish the issuer runtime image

The Eclipse EDC `MinimumViableDataspace` project does not publish ready-made issuer images. Its README explicitly says adopters must build from source.

Helper script:

```bash
./scripts/build-mvd-issuer-image.sh /path/to/MinimumViableDataspace ghcr.io/your-org/issuerservice:latest
```

After pushing the image, update:

- `platform-apps/gxdch-issuer/core/issuer-deployment.yaml`

and replace:

```text
ghcr.io/REPLACE_ME/issuerservice:latest
```

with your real image reference.

### 2. Generate issuer bootstrap material

Before syncing the stack, generate:

- a P-256 private key for Vault as `statuslist-signing-key`
- an Ed25519 `did:web` document for the issuer host

Helper script:

```bash
./scripts/generate-issuer-bootstrap.sh dataspace-issuer.example.com gxdch-issuer > issuer-bootstrap.yaml
kubectl apply -f issuer-bootstrap.yaml
```

The first argument can be either:

- a dedicated hostname, for example `issuer.gxdch.dil.collab-cloud.eu`
- or a host plus path, for example `gxdch.dil.collab-cloud.eu/issuer`

For the path-based example, the resulting DID will be:

```text
did:web:gxdch.dil.collab-cloud.eu:issuer
```

and the DID document will be expected at:

```text
https://gxdch.dil.collab-cloud.eu/issuer/did.json
```

Internally, the bundled NGINX server now serves the DID document at:

```text
/did.json
```

so your gateway should rewrite:

```text
/issuer/did.json -> /did.json
```

This creates:

- `Secret/issuer-bootstrap`
- `ConfigMap/dataspace-issuer-did-config`

The stack expects those resources to exist before sync.

The generated DID document is only a public document; it does not create the
issuer participant or its signing key in the Identity API. The issuer
participant must be provisioned after the service starts, and the generated
public `x` value must be copied into the DID document. The helper accepts that
value through `DID_PUBLIC_KEY_X`:

```bash
DID_PUBLIC_KEY_X='<x from keypair_resource.serialized_public_key>' \
  ./scripts/generate-issuer-bootstrap.sh gxdch.dil.collab-cloud.eu/issuer gxdch-issuer \
  | kubectl apply -f -
```

## Bootstrap

1. Push this repository to GitHub.
2. Build and publish the issuer image.
3. Update the image reference in `issuer-deployment.yaml`.
4. Generate and apply the bootstrap manifest:

```bash
./scripts/generate-issuer-bootstrap.sh gxdch.dil.collab-cloud.eu/issuer gxdch-issuer | kubectl apply -f -
```

5. Apply the root ArgoCD application:

```bash
kubectl apply -n argocd -f platform-apps/argocd/gxdch-issuer-application.yaml
```

### Provision the issuer participant

The current `issuerservice` image exposes participant management at
`v1alpha`. Use the super-user API key configured by
`EDC_IH_API_SUPERUSER_KEY`:

```bash
ISSUER_DID='did:web:gxdch.dil.collab-cloud.eu:issuer'
SUPERUSER_KEY='<EDC_IH_API_SUPERUSER_KEY>'

curl -fsS -X POST \
  'https://gxdch.dil.collab-cloud.eu/issuer/api/identity/v1alpha/participants' \
  -H 'content-type: application/json' \
  -H "x-api-key: ${SUPERUSER_KEY}" \
  -d "$(jq -n --arg did "$ISSUER_DID" '{
    participantId: $did,
    did: $did,
    active: true,
    roles: [],
    serviceEndpoints: [],
    key: {
      keyId: "key-1",
      privateKeyAlias: "gxdch-issuer-key-1",
      keyGeneratorParams: { algorithm: "EdDSA", curve: "Ed25519" }
    }
  }')"
```

The response contains participant API credentials; store them outside Git. Read
the generated public key from `keypair_resource.serialized_public_key`, set
`DID_PUBLIC_KEY_X` to its `x` value, reapply the bootstrap manifest, and
restart the static DID server. The `x` in `did.json` and the `x` in the stored
key must be identical.

If the issuer signs membership credentials with a dedicated credential key,
also publish that key in the DID document. Set
`DID_CREDENTIAL_PUBLIC_KEY_X` to the `x` value of the active
`sign_credentials` key when generating the bootstrap manifest:

```bash
DID_PUBLIC_KEY_X='<issuer sign_token x>' \
DID_CREDENTIAL_PUBLIC_KEY_X='<issuer sign_credentials x>' \
  ./scripts/generate-issuer-bootstrap.sh gxdch.dil.collab-cloud.eu/issuer gxdch-issuer \
  | kubectl apply -f -
```

## Services and Ports

- `dataspace-issuer-service`
  - `10010` web health
  - `10011` STS
  - `10012` issuance API
  - `10013` issuer admin API
  - `10015` identity API
  - `10016` DID endpoint in the issuer runtime
- `dataspace-issuer`
  - `80` static `did:web` hosting through NGINX
- `issuer-postgres`
  - `5432`
- `issuer-vault`
  - `8200`

## Suggested Envoy Gateway Routes

The most important externally reachable endpoints are:

- `https://gxdch.dil.collab-cloud.eu/issuer/did.json` -> `dataspace-issuer:80` with prefix rewrite to `/did.json`
- `https://issuer.example.com/api/admin/` -> `dataspace-issuer-service:10013`
- `https://issuer.example.com/api/issuance/` -> `dataspace-issuer-service:10012`
- `https://issuer.example.com/api/identity/` -> `dataspace-issuer-service:10015`

You can host all runtime APIs on one hostname and the DID on another, or reuse a single hostname if your routing rules preserve the paths.

## Operational Notes

- Vault is deployed in dev mode for simplicity. This is not production-grade.
- Vault dev mode is in-memory. A Vault restart loses generated participant
  private keys; production requires a persistent, initialized Vault.
- PostgreSQL uses a single PVC and local credentials from a Kubernetes Secret.
- The issuer still needs post-deploy administrative setup for holders and issuance flows.
- Participant-side `Identity Hub` and `EDC` runtimes still belong in `gx-participant1` and `gx-participant2`, not here.

## Recovery Notes

The `gxdch` tenant was reset after its vCluster syncer entered a crash loop
while parsing an empty stale `/data/pids/apiserver.pid`. The old vCluster PVC
was removed and recreated. The issuer service also had a PostgreSQL startup
race; the deployment now waits for `issuer-postgres` before starting
`issuerservice`. The gateway must route the DID, Identity API, STS, issuance,
and issuer-admin paths to their corresponding services; a DID-only route is
not sufficient for DCP.

## Sources

Primary sources used for this repo design:

- Eclipse EDC MinimumViableDataspace: https://github.com/eclipse-edc/MinimumViableDataspace
- Gaia-X OIDC4VC ICAM document: https://docs.gaia-x.eu/technical-committee/identity-credential-access-management/24.07/oidc_integration/
- Gaia-X architecture document: https://docs.gaia-x.eu/technical-committee/architecture-document/latest/gaia-x_technical_compatibility_specifications/
