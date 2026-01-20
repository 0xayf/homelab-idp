# Secrets Management Platform

This document describes the secrets management architecture built on HashiCorp Vault, Crossplane, and External Secrets Operator (ESO). It covers how Vault is deployed, how secrets flow between systems, how namespaces are onboarded, and how applications consume secrets.

---

## Table of Contents

- [Concepts](#concepts)
- [Architecture Overview](#architecture-overview)
- [Vault Deployment](#vault-deployment)
  - [Helm Chart](#helm-chart)
  - [Bootstrap Sequence](#bootstrap-sequence)
  - [Token Lifecycle](#token-lifecycle)
- [Vault Path Structure](#vault-path-structure)
- [Crossplane Compositions](#crossplane-compositions)
  - [Primitive Compositions](#primitive-compositions)
  - [Secret Compositions](#secret-compositions)
- [Namespace Onboarding](#namespace-onboarding)
  - [Step-by-Step Walkthrough](#step-by-step-walkthrough)
  - [What Gets Created](#what-gets-created)
- [Credential Flows](#credential-flows)
  - [Random Secret Flow](#random-secret-flow)
  - [UserPass Secret Flow](#userpass-secret-flow)
  - [Registry Credential Flow](#registry-credential-flow)
- [How Applications Consume Secrets](#how-applications-consume-secrets)
- [Provider Configuration](#provider-configuration)
- [Troubleshooting Reference](#troubleshooting-reference)

---

## Concepts

If you are unfamiliar with the tools involved, here is a brief primer.

### HashiCorp Vault

Vault is a secrets management system. Think of it as a secure, centralised key-value store with fine-grained access control. Instead of scattering passwords across Kubernetes secrets, config files, and environment variables, everything is stored in Vault and pulled on demand. Vault provides:

- **Encryption at rest** — secrets are encrypted before they hit disk.
- **Access policies** — each consumer gets a policy defining exactly which paths it can read or write.
- **Audit logging** — every secret access is logged.
- **Dynamic secrets** — Vault can generate short-lived credentials (not used in this platform yet, but the capability exists).

Vault organises secrets into **secret engines** mounted at specific paths. This platform uses the **KV v2** engine, which provides versioned key-value storage.

### External Secrets Operator (ESO)

ESO is a Kubernetes operator that synchronises secrets from external stores (like Vault) into native Kubernetes Secrets. It introduces several custom resources:

| Resource | Purpose |
|---|---|
| `SecretStore` | Defines how to connect to a secret backend (Vault address, auth method, mount path) — scoped to a single namespace. |
| `ExternalSecret` | Declares which keys to pull from the backend and how to map them into a Kubernetes Secret. |
| `PushSecret` | The reverse — pushes data from a Kubernetes Secret into the backend (Vault). |
| `Password` (generator) | Generates a random password conforming to length and character constraints. |

### Crossplane

Crossplane extends Kubernetes with custom resource definitions (CRDs) that let you provision infrastructure declaratively. In this platform, Crossplane compositions wrap the low-level Vault and Kubernetes provider resources behind simple, opinionated claim APIs. Instead of writing 5 YAML files to create a secret, you write one claim.

### How They Work Together

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer                                │
│                                                                 │
│   kubectl apply -f my-secret-claim.yaml                         │
│       apiVersion: secrets.platform.lab/v1alpha1                 │
│       kind: UserPass                                            │
│       spec:                                                     │
│         username: my-app                                        │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Crossplane                                  │
│                                                                 │
│   Composition resolves the claim into concrete resources:       │
│   - Password generator (ESO)                                    │
│   - ExternalSecret (renders K8s Secret from generator)          │
│   - PushSecret (syncs K8s Secret → Vault)                       │
└───────────────────────────┬─────────────────────────────────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
    ┌──────────────┐ ┌────────────┐ ┌───────────┐
    │ ESO Password │ │ PushSecret │ │ External  │
    │  Generator   │ │  → Vault   │ │  Secret   │
    │ (generates)  │ │  (writes)  │ │  (reads)  │
    └──────┬───────┘ └─────┬──────┘ └─────┬─────┘
           │               │             │
           ▼               ▼             ▼
    ┌──────────────┐ ┌───────────┐ ┌────────────┐
    │  K8s Secret  │ │   Vault   │ │ K8s Secret │
    │  (ephemeral) │ │  KV Store │ │   (final)  │
    └──────────────┘ └───────────┘ └────────────┘
                     Source of       App mounts
                      truth           this one
```

---

## Architecture Overview

```
                    ┌──────────────────────────────────────────────────┐
                    │               Vault (vault namespace)            │
                    │                                                  │
                    │   Standalone server: vault-0                     │
                    │   Internal: http://vault-0.vault-internal:8200   │
                    │   Cross-NS: http://vault.vault.svc.cluster.local:8200 │
                    │   UI: https://secrets.lab                        │
                    │                                                  │
                    │   Auth Methods:                                  │
                    │   ├── Token (root + crossplane periodic)         │
                    │   └── Kubernetes (path: kubernetes)              │
                    │                                                  │
                    │   Secret Engines:                                │
                    │   └── platform/<namespace>/kv (KV v2, per-NS)    │
                    │                                                  │
                    └──────────────────┬───────────────────────────────┘
                                       │
                    ┌──────────────────┼───────────────────────┐
                    │                  │                       │
              ┌─────▼──────┐    ┌───────▼───────┐    ┌────────▼────────┐
              │ Crossplane │    │   External    │    │   Applications  │
              │            │    │   Secrets     │    │                 │
              │ Uses token │    │   Operator    │    │  Mount secrets  │
              │ auth with  │    │               │    │  from K8s       │
              │ crossplane │    │  Uses K8s     │    │  Secret objects │
              │ policy     │    │  auth with    │    │                 │
              │ (full      │    │  per-NS       │    │                 │
              │  access)   │    │  policies     │    │                 │
              └────────────┘    └───────────────┘    └─────────────────┘
```

There are two distinct authentication paths into Vault:

1. **Crossplane** authenticates with a **periodic token** (stored in `vault:crossplane-vault-token`). This token has a broad `crossplane` policy granting full access to all paths. Crossplane uses this to create and manage Vault resources (mounts, policies, auth roles, secrets).

2. **External Secrets Operator** authenticates with **Kubernetes auth** — each namespace gets its own SecretStore that authenticates via a ServiceAccount. Policies are scoped per-namespace so a SecretStore in namespace `foo` can only read/write `platform/foo/kv/*`.

---

## Vault Deployment

### Helm Chart

Vault is deployed as a wrapper Helm chart located at `platform-core/security/vault/`.

Key decisions:
- **Standalone mode** — single-node k3s cluster, so no HA.
- **Injector disabled** — secrets are delivered via ESO, not sidecar injection.
- **`local-path` storage class** — k3s default, backed by node-local disk.
- **UI enabled** at `secrets.lab` — accessible via ingress-nginx with TLS from cert-manager (`lab-ca-issuer`).

### Bootstrap Sequence

Vault requires a multi-step bootstrap process before it can serve secrets. This is orchestrated through ArgoCD sync hooks, ordered by sync-wave.

```
Wave 0 ─── init-job.yaml
            │  Initialise Vault (if uninitialised)
            │  Unseal Vault (if sealed)
            │  Store root token + unseal keys
            ▼
Wave 1-2 ── vault-bootstrap-job.yaml
            │  Create 'crossplane' policy (full access)
            │  Create/validate periodic token (720h renewal)
            │  Store token in crossplane-vault-token secret
            ▼
Wave 3 ──── k8s-auth-backend-claim.yaml
            │  Enable Kubernetes auth backend
            │  Configure K8s API host + CA
            ▼
Wave 4 ──── external-secrets.yaml
            │  Create ESO policy (platform/* access)
            │  Bind external-secrets SA (all namespaces)
            │  to external-secrets policy
            ▼
Cron ────── crossplane-token-renew-cronjob.yaml
            Weekly token renewal (Sunday midnight)
```

#### Wave 0: Vault Initialisation (`init-job.yaml`)

An ArgoCD sync hook Job that runs on every sync. It:

1. Waits for the Vault API to become available at `http://vault-0.vault-internal:8200`.
2. Checks `/v1/sys/health` for initialisation status.
3. **If uninitialised**: calls `PUT /v1/sys/init` with 3 key shares and threshold of 3, then stores the root token and all 3 unseal keys in a Kubernetes Secret called `init-credentials` in the `vault` namespace.
4. **If sealed**: retrieves unseal keys from the secret and calls `PUT /v1/sys/unseal` three times.
5. **If already initialised and unsealed**: does nothing.

The `init-credentials` secret contains:
```
root-token:    <Vault root token>
unseal-key-1:  <base64 unseal key>
unseal-key-2:  <base64 unseal key>
unseal-key-3:  <base64 unseal key>
```

> **Security note:** The root token and unseal keys are stored as a Kubernetes Secret. In a production environment you would use a cloud-based auto-unseal and revoke the root token after initial setup. This is a homelab configuration.

#### Wave 1–2: Crossplane Token Bootstrap (`vault-bootstrap-job.yaml`)

After Vault is initialised and unsealed, this Job:

1. Reads the root token from `init-credentials`.
2. Creates a Vault policy named `crossplane`:
   ```hcl
   path "*" {
     capabilities = ["create", "read", "update", "delete", "list", "sudo"]
   }
   ```
   This gives Crossplane full administrative access to Vault.
3. Checks if a valid `crossplane-vault-token` secret already exists:
   - If the token exists and is valid with the `crossplane` policy → keeps it.
   - If the token exists but is expired or missing the policy → creates a new one.
   - If no token exists → creates a new one.
4. Creates a **periodic token** with a 720-hour (30-day) period:
   ```
   POST /v1/auth/token/create
   {"policies": ["crossplane"], "period": "720h", "display_name": "crossplane-provider"}
   ```
   A periodic token never expires as long as it is renewed within its period window.
5. Stores the token in the `crossplane-vault-token` secret in JSON format:
   ```json
   {"token": "hvs.CAESIJ..."}
   ```

#### Wave 3: Kubernetes Auth Backend (`k8s-auth-backend-claim.yaml`)

This uses the platform's own `K8sAuthBackend` Crossplane claim:

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: K8sAuthBackend
metadata:
  name: vault-k8s-auth-backend
spec:
  path: kubernetes
  createBackend: true
  kubernetesHost: https://kubernetes.default.svc
  disableLocalCaJwt: false
```

This enables Vault's Kubernetes authentication method, which allows pods to authenticate using their ServiceAccount token. The composition creates:
- An `auth.vault.m.upbound.io/v1alpha1/Backend` (the auth mount itself)
- A `kubernetes.vault.m.upbound.io/v1alpha1/AuthBackendConfig` (pointing Vault at the K8s API server)

#### Wave 4: External Secrets Policy and Role

**Policy** (`external-secrets.yaml`):
```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: Policy
metadata:
  name: external-secrets
spec:
  policyDocument: |
    path "platform/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    path "platform/data/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
    path "platform/metadata/*" {
      capabilities = ["create", "read", "update", "delete", "list"]
    }
```

This grants full CRUD access to everything under `platform/`. The `data/` and `metadata/` paths are required because KV v2 internally nests data under `<mount>/data/<key>` and metadata under `<mount>/metadata/<key>`.

**AuthRole** (`external-secrets.yaml`):
```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: AuthRole
metadata:
  name: external-secrets-auth
spec:
  backend: kubernetes
  roleName: external-secrets
  boundServiceAccountNames:
    - external-secrets
  boundServiceAccountNamespaces:
    - "*"
  policyNames:
    - external-secrets
  tokenTtl: 3600
```

This binds the `external-secrets` ServiceAccount **from any namespace** to the `external-secrets` policy. When ESO's SecretStore authenticates to Vault, it presents the `external-secrets` SA token and receives a Vault token scoped to `external-secrets`.

> **Note:** There is a two-tier policy model. The global `external-secrets` policy (created in the `vault` namespace) gives broad access to `platform/*`. Additionally, each namespace gets its own scoped policy during onboarding (for example `platform/<namespace>/kv/data/*`). In this repo, SecretStores are typically configured with namespace-specific roles (for example `<namespace>` or `<namespace>-auth`); the global role remains available as a broad fallback.

### Token Lifecycle

The Crossplane periodic token has a 720-hour (30-day) period. A CronJob runs every Sunday at midnight to renew it:

```
POST /v1/auth/token/renew-self
X-Vault-Token: <crossplane-token>
```

If renewal fails, the CronJob exits with code 1, which will appear in Kubernetes Job history (`failedJobsHistoryLimit: 3`).

The token renewal chain:
```
Token created (720h period)
    │
    ├── Week 1: CronJob renews → TTL resets to 720h
    ├── Week 2: CronJob renews → TTL resets to 720h
    ├── ...
    └── If missed for 30 days → token expires → Crossplane loses Vault access
        → vault-bootstrap-job can recreate it on a subsequent ArgoCD sync
```

---

## Vault Path Structure

All platform secrets live under the `platform/` prefix. Each namespace gets its own KV v2 engine mount.

```
platform/
└── <namespace>/
    └── kv/                          ← KV v2 engine mount
        ├── <secret-name>            ← Individual secrets
        │   ├── password
        │   ├── username
        │   └── ...
        └── registry/
            └── <token-name>         ← Registry token credentials
                └── password
```

KV v2 internals: when you write to `platform/myns/kv/my-secret`, Vault actually stores it at `platform/myns/kv/data/my-secret`. The `data/` and `metadata/` prefixes are implicit in the API. This is why policies need to cover both `kv/data/*` and `kv/metadata/*`.

---

## Crossplane Compositions

### Primitive Compositions

These are low-level building blocks that other compositions and onboarding scripts use.

#### KVMount

Creates a KV v2 secrets engine in Vault.

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: KVMount
metadata:
  name: kv-mount
  namespace: my-namespace
spec:
  description: "KV v2 secrets engine managed by Crossplane"  # optional
```

Creates: `vault.vault.m.upbound.io/v1alpha1/Mount` at path `platform/<namespace>/kv` with type `kv-v2`.

Status: `mountPath` — the full Vault mount path (e.g., `platform/my-namespace/kv`).

#### Policy

Creates a Vault policy. Can be auto-generated from engine list or provided as raw HCL.

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: Policy
metadata:
  name: my-policy
  namespace: my-namespace
spec:
  # Option A: Auto-generate rules for specific engines
  accessMode: readwrite    # or "read"
  engines:
    - kv

  # Option B: Provide raw policy document (overrides accessMode/engines)
  # policyDocument: |
  #   path "platform/*" { capabilities = ["read", "list"] }
```

When using `accessMode` + `engines`, the composition generates:
- For `kv` engine with `readwrite`:
  ```hcl
  path "platform/<namespace>/kv/data/*" {
    capabilities = ["create", "read", "update", "patch", "delete", "list"]
  }
  path "platform/<namespace>/kv/metadata/*" {
    capabilities = ["create", "read", "update", "patch", "delete", "list"]
  }
  ```
- For `read` mode, capabilities are `["read", "list"]` only.

Status: `policyName` — the Vault policy name.

#### K8sAuthBackend

Configures Vault's Kubernetes authentication method.

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: K8sAuthBackend
metadata:
  name: my-auth-backend
spec:
  path: kubernetes              # Vault auth mount path (default: kubernetes)
  createBackend: true           # Create the mount if it doesn't exist (default: false)
  kubernetesHost: https://kubernetes.default.svc  # K8s API (default)
  disableLocalCaJwt: false      # Use pod's local SA JWT and CA (default: false)
  # kubernetesCaCert: |         # Optional: explicit CA cert PEM
```

Creates:
- `auth.vault.m.upbound.io/v1alpha1/Backend` (if `createBackend: true`)
- `kubernetes.vault.m.upbound.io/v1alpha1/AuthBackendConfig`

Status: `backendPath` — the effective auth mount path.

#### AuthRole

Binds Kubernetes ServiceAccounts to Vault policies via the Kubernetes auth backend.

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: AuthRole
metadata:
  name: my-auth-role
  namespace: my-namespace
spec:
  backend: kubernetes                        # Auth backend path (default: kubernetes)
  roleName: my-custom-role-name              # Vault role name (default: metadata.name)
  boundServiceAccountNames:
    - external-secrets                       # K8s SAs that can authenticate (default: [external-secrets])
  boundServiceAccountNamespaces:
    - my-namespace                           # K8s namespaces allowed (default: [claim namespace])
  policyNames:                               # REQUIRED
    - my-policy
  tokenTtl: 3600                             # Token TTL in seconds (default: 3600)
```

Creates: `kubernetes.vault.m.upbound.io/v1alpha1/AuthBackendRole`.

Status: `roleName` — the effective Vault role name.

### Secret Compositions

These are the higher-level compositions that developers use to manage secrets.

#### Random

Generates a random password, stores it in Vault, and projects it as a Kubernetes Secret.

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: Random
metadata:
  name: api-key
  namespace: my-namespace
spec:
  length: 32             # 16–128, default: 32
  includeSymbols: false  # default: false (symbols: -_$@!#%)
```

Resource pipeline:
1. **Password generator** (`generators.external-secrets.io/v1alpha1/Password`) — generates a random password matching the spec.
2. **PushSecret** — pushes the generated password to Vault at `platform/<namespace>/kv/<name>` with property `password`. Uses `updatePolicy: IfNotExists` so the password is stable once created.
3. **ExternalSecret** — reads the password back from Vault and creates a Kubernetes Secret named `<name>` with key `password`.

Result:
- Vault: `platform/<namespace>/kv/<name>` → `{ "password": "<random>" }`
- K8s Secret: `<name>` in `<namespace>` → `data.password`

#### UserPass

Generates a username/password pair with optional output templating. More flexible than Random — supports structured credentials (e.g., JSON connection strings).

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: UserPass
metadata:
  name: my-credentials
  namespace: my-namespace
spec:
  username: my-app            # default: metadata.name
  length: 32                  # 16–128, default: 32
  includeSymbols: false       # default: false

  # Optional: render a templated output key
  outputTemplate:
    secretKey: credentials    # Key name in final secret (default: credentials)
    onlyTemplate: false       # If true, omit username/password keys (default: false)
    template: '{"base_url":"{{ .base_url }}","username":"{{ .username }}","password":"{{ .password }}"}'
    values:                   # Static substitution values
      base_url: http://my-service:8080
```

---

## Namespace Onboarding

Before a namespace can use `Random`, `UserPass`, or any secret composition, it needs a set of foundational resources. The onboarding claim (`example-claims/secrets/onboarding-claim.yaml`) shows the pattern.

### Step-by-Step Walkthrough

**1. Create a KV Mount**

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: KVMount
metadata:
  name: kv-mount
  namespace: my-namespace
spec: {}
```

This creates a Vault KV v2 engine at `platform/my-namespace/kv`.

**2. Create an External Secrets ServiceAccount**

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-secrets
  namespace: my-namespace
```

This is the identity ESO uses when authenticating to Vault via Kubernetes auth.

**3. Create a SecretStore**

```yaml
apiVersion: external-secrets.io/v1
kind: SecretStore
metadata:
  name: my-namespace-secret-store
  namespace: my-namespace
spec:
  provider:
    vault:
      server: "http://vault.vault.svc.cluster.local:8200"
      path: "platform/my-namespace/kv"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "my-namespace-auth"
          serviceAccountRef:
            name: "external-secrets"
            namespace: "my-namespace"
```

The SecretStore connects ESO to Vault. It:
- Points at the namespace-specific KV mount path.
- Authenticates using the `external-secrets` ServiceAccount against the `my-namespace-auth` Vault role.
- Uses KV v2 API (`version: "v2"`).

**4. Create a Vault Policy**

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: Policy
metadata:
  name: my-namespace-kv-policy
  namespace: my-namespace
spec:
  accessMode: readwrite
  engines:
    - kv
```

Generates a policy granting readwrite access to `platform/my-namespace/kv/data/*` and `platform/my-namespace/kv/metadata/*`.

**5. Create an AuthRole**

```yaml
apiVersion: secrets.platform.lab/v1alpha1
kind: AuthRole
metadata:
  name: my-namespace-auth
  namespace: my-namespace
spec:
  backend: kubernetes
  roleName: my-namespace-auth
  boundServiceAccountNames:
    - external-secrets
  policyNames:
    - my-namespace-kv-policy
  tokenTtl: 3600
```

Binds the namespace's `external-secrets` SA to the policy created above.

### What Gets Created

After onboarding, the namespace has:

```
Vault:
  ├── Mount: platform/my-namespace/kv (KV v2)
  ├── Policy: my-namespace-kv-policy
  │   └── path "platform/my-namespace/kv/data/*" { capabilities = [CRUD] }
  │   └── path "platform/my-namespace/kv/metadata/*" { capabilities = [CRUD] }
  └── Auth Role: my-namespace-auth
      └── Bound SA: external-secrets @ my-namespace
      └── Policies: [my-namespace-kv-policy]

Kubernetes (my-namespace):
  ├── ServiceAccount: external-secrets
  └── SecretStore: my-namespace-secret-store
      └── → Vault @ platform/my-namespace/kv (k8s auth, role: my-namespace-auth)
```

The naming convention `<namespace>-secret-store` is hardcoded in the `Random` and `UserPass` compositions:
```go
$secretStoreName := printf "%s-secret-store" $namespace
```

This means the SecretStore **must** follow this naming pattern or the compositions will fail.

---

## Credential Flows

### Random Secret Flow

```
Developer applies Random claim
         │
         ▼
Crossplane creates ESO Password generator
         │  (generates random string)
         ▼
Crossplane creates PushSecret
         │  (updatePolicy: IfNotExists)
         │  K8s Secret (generated) ──push──→ Vault KV
         ▼
Crossplane creates ExternalSecret
         │
         │  Vault KV ──pull──→ K8s Secret (final)
         ▼
App mounts K8s Secret "<name>"
   key: password
```

### UserPass Secret Flow

```
Developer applies UserPass claim
         │
         ▼
Crossplane creates ESO Password generator
         │  (named: <name>-password)
         ▼
Crossplane creates ExternalSecret (local)
         │  Uses generatorRef to get password
         │  Renders template with username + password
         │  Creates K8s Secret "<name>"
         ▼
Crossplane creates PushSecret
         │  (updatePolicy: Replace)
         │  K8s Secret "<name>" ──push──→ Vault KV
         ▼
App mounts K8s Secret "<name>"
   keys: username, password [, credentials]
```

Note the difference from Random: UserPass uses `updatePolicy: Replace` (not `IfNotExists`), meaning the secret in Vault is updated if the K8s Secret changes.

### Registry Credential Flow

The registry domain (`registry.platform.lab`) provisions Gitea users, repositories, teams, and access tokens. The token composition has the most complex credential flow:

```
Developer applies Token claim
         │
         ├──→ ProviderConfig (namespaced, per-user auth)
         │      Reads auth credentials from authSecretRef
         │      (typically a UserPass-generated JSON secret)
         │
         ├──→ Gitea Token resource
         │      Creates access token via Gitea API
         │      Writes raw token to K8s Secret "<name>-token-raw"
         │
         ├──→ PushSecret
         │      Pushes token to Vault at platform/<ns>/kv/registry/<name>
         │      Property: password (the token value)
         │
         └──→ ExternalSecret
                Pulls token from Vault
                Creates K8s Secret "<name>-registry"
                Type: kubernetes.io/dockerconfigjson
                Renders .dockerconfigjson with auth for <registryHost>/<org>/<repo>
```

`registryHost` comes from `Token.spec.registryHost` (defaults to `git.lab`). Set it explicitly if your Gitea hostname differs.

The final Secret can be used as an `imagePullSecret` in pod specs.

---

## How Applications Consume Secrets

Applications never interact with Vault directly. They consume secrets through standard Kubernetes Secrets created by ExternalSecrets.

### Example: Using a Random Secret

```yaml
# 1. Create the secret
apiVersion: secrets.platform.lab/v1alpha1
kind: Random
metadata:
  name: api-key
  namespace: my-app
spec: {}

# 2. Reference it in your Deployment
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: app
        env:
        - name: API_KEY
          valueFrom:
            secretKeyRef:
              name: api-key        # Same as claim name
              key: password
```

### Example: Using a UserPass Secret

```yaml
# 1. Create credentials
apiVersion: secrets.platform.lab/v1alpha1
kind: UserPass
metadata:
  name: my-service-creds
  namespace: my-app
spec:
  username: my-service

# 2. Mount as environment variables
env:
- name: DB_USERNAME
  valueFrom:
    secretKeyRef:
      name: my-service-creds
      key: username
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: my-service-creds
      key: password
```

### Example: Using Registry Credentials

```yaml
# After Token claim creates "<name>-registry" secret:
spec:
  template:
    spec:
      imagePullSecrets:
      - name: my-token-registry
```

### Secret Naming Convention

| Claim Type | K8s Secret Name | Keys |
|---|---|---|
| `Random` | `<name>` | `password` |
| `UserPass` | `<name>` | `username`, `password`, optionally `<outputTemplate.secretKey>` |
| `Token` | `<name>-registry` | `.dockerconfigjson` |

---

## Provider Configuration

### Vault Crossplane Provider

| Provider | Role | Auth |
|---|---|---|
| `provider-vault` (Upbound) | Manages Vault resources (mounts, policies, auth roles) | Periodic token in `vault:crossplane-vault-token` |

### ProviderConfig Name

| Config Name | Type | Used By |
|---|---|---|
| `vault-provider-config` | `ClusterProviderConfig` | All Vault compositions (Policy, KVMount, AuthRole, K8sAuthBackend) |

### Vault Addresses

| Context | Address |
|---|---|
| Within `vault` namespace (bootstrap jobs) | `http://vault-0.vault-internal:8200` |
| Cross-namespace (SecretStores, applications) | `http://vault.vault.svc.cluster.local:8200` |
| External (browser UI) | `https://secrets.lab` |

---

## Troubleshooting Reference

### Useful Commands

```bash
# Check Vault status
kubectl exec vault-0 -n vault -- vault status

# Check Vault seal status
kubectl exec vault-0 -n vault -- vault status -format=json | jq .sealed

# List all SecretStores and their status
kubectl get secretstores -A

# Check ExternalSecret sync status
kubectl get externalsecrets -A

# Check PushSecret sync status
kubectl get pushsecrets -A

# View Crossplane managed resources
kubectl get managed

# Check a specific composition's resources
kubectl get composite -A

# Validate compositions render correctly
helm template test controlplane/crossplane-compositions --include-crds

# View Crossplane composition function logs
kubectl logs -n crossplane-system -l pkg.crossplane.io/revision --tail=50
```
