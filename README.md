# gitops-flux-workshop

## References

* [Flux core concepts](https://fluxcd.io/flux/concepts/)
* [Flux installation](https://fluxcd.io/flux/installation/)
* [GitOps Toolkit components](https://fluxcd.io/flux/components/)
* [`GitRepository`](https://fluxcd.io/flux/components/source/gitrepositories/)
* [Flux `Kustomization`](https://fluxcd.io/flux/components/kustomize/kustomizations/)
* [Helm controller](https://fluxcd.io/flux/components/helm/)
* [Image automation controllers](https://fluxcd.io/flux/components/image/)
* [Notification controller](https://fluxcd.io/flux/components/notification/)
* [Flux repository structures](https://fluxcd.io/flux/guides/repository-structure/)
* [Flux with SOPS](https://fluxcd.io/flux/guides/mozilla-sops/)
* [Flux security](https://fluxcd.io/flux/security/)

## Workshop warning

This repository commits a disposable age private identity in
[`local-setup/workshop.agekey`](./local-setup/workshop.agekey).

* it makes the workshop reproducible
* it provides no confidentiality because anyone with repository access can decrypt the files
* `.sourceignore` keeps it out of the Flux source artifact but does not make committing it safe
* production private identities must be delivered outside Git

## Goals

* install Flux on Docker Desktop Kubernetes
* connect Flux to this Git repository
* follow a Git revision from `GitRepository` to applied resources
* distinguish Flux `Kustomization` from Kustomize `kustomization.yaml`
* operate dev and prod nginx overlays
* observe readiness, dependencies, retries, drift correction and pruning
* understand SOPS decryption from Flux's perspective
* identify where Helm, image automation and notifications fit

The workshop assumes the Kustomize and SOPS concepts from the prerequisite
workshops. It does not repeat their general theory.

## Example workload

Nginx is an intentionally small workload. There is no application project or
image build.

| Environment | Namespace | Replicas | HTTP response |
| --- | --- | ---: | --- |
| dev | `nginx-dev` | 1 | `environment: dev` |
| prod | `nginx-prod` | 2 | `environment: prod` |

Each overlay supplies an environment-specific `ConfigMap`. The Deployment
mounts its `index.html` at `/usr/share/nginx/html`.

## GitOps model

* Git records the reviewed desired state and its history
* controllers inside the cluster pull that state instead of requiring CI to push with cluster credentials
* reconciliation repeatedly moves the cluster toward the selected Git revision
* manual changes remain possible but managed fields are restored from Git
* promotion is a Git change, normally reviewed through a pull request

Git is the desired-state source, not the running-state database. Kubernetes
status remains the source for current health, failures and observed state.

## Flux architecture

Flux is a set of Kubernetes controllers. Each controller watches Kubernetes
custom resources and reports its result through status conditions and events.

```text
Git
  ↓
source-controller
  ↓ GitRepository artifact
kustomize-controller
  ↓ decrypt → build → validate → apply
Kubernetes API
  ↓
Deployment, Service, ConfigMap and Secret
```

Default installation components:

* `source-controller`
  * fetches Git, OCI, Helm and bucket sources
  * produces immutable artifacts for resolved source revisions
* `kustomize-controller`
  * reads source artifacts
  * decrypts SOPS resources when configured
  * builds, validates, applies, checks and prunes Kubernetes resources
* `helm-controller`
  * reconciles declarative Helm releases
* `notification-controller`
  * accepts inbound webhook events
  * sends selected Flux events to external providers

Optional image automation components:

* `image-reflector-controller` scans registries and evaluates image policies
* `image-automation-controller` writes selected image updates back to Git

The default `flux install` does not install the two image controllers.

## Installation and bootstrap

### Installation

`flux install` installs Flux CRDs and controllers in the cluster.

It does not:

* connect the cluster to this repository
* create this workshop's `GitRepository`
* create this workshop's Flux `Kustomization` resources
* store the installation manifests in Git

The workshop uses installation so each connection resource can be inspected and
applied explicitly.

### Bootstrap

`flux bootstrap`:

* installs or upgrades the controllers
* writes the Flux installation manifests to a Git repository
* creates the source and synchronization resources
* configures Flux to manage its own installation from Git
* can configure provider-specific deploy keys

Bootstrap is idempotent and is the recommended approach for a long-lived Flux
installation. Installation alone is useful for this focused learning flow.

## Source and artifact

[`clusters/source.yaml`](./clusters/source.yaml) defines the workshop source:

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-flux-workshop
  namespace: flux-system
spec:
  interval: 1m
  url: https://github.com/mtumilowicz/gitops-flux-workshop.git
  ref:
    branch: main
```

Fields:

* `metadata.name` and `metadata.namespace` identify the source object
* `spec.url` identifies the remote Git repository
* `spec.ref.branch` selects `main`
* `spec.interval` schedules a source check every minute

On successful reconciliation, `source-controller`:

1. resolves `main` to a commit
2. archives the selected repository content as a compressed artifact
3. stores its revision, digest, size and in-cluster URL in `.status.artifact`
4. emits an event when a new artifact revision is available

`.sourceignore` excludes `local-setup/` when the artifact is created. The
artifact is therefore derived from the Git revision but does not have to contain
every file in that revision.

## `sourceRef` and `spec.path`

All four Flux `Kustomization` resources reference the same source:

```yaml
sourceRef:
  kind: GitRepository
  name: gitops-flux-workshop
```

`sourceRef` identifies a Kubernetes source object. It is not a Git URL.

`sourceRef.namespace` is omitted because the source and the Flux
`Kustomization` are all in `flux-system`. An explicit namespace is required for
an allowed cross-namespace reference.

`spec.path` starts at the root of the source artifact:

```text
GitRepository artifact root
└── apps/nginx/overlays/dev
    └── kustomization.yaml
```

Therefore [`clusters/dev/nginx.yaml`](./clusters/dev/nginx.yaml) uses:

```yaml
path: ./apps/nginx/overlays/dev
```

The path is not relative to `clusters/dev/nginx.yaml`. Changing it to
`./overlays/dev` would select a nonexistent artifact directory and cause the
reconciliation to fail.

## Two `Kustomization` resources

Flux and Kustomize use the same word for different resources.

| Resource | Example | Read by | Purpose |
| --- | --- | --- | --- |
| Flux `Kustomization` | `clusters/dev/nginx.yaml` | `kustomize-controller` | continuously reconciles a source path |
| Kustomize `kustomization.yaml` | `apps/nginx/overlays/dev/kustomization.yaml` | Kustomize library or `kubectl kustomize` | renders a set of manifests |

The complete relationship is:

```text
clusters/dev/nginx.yaml
  sourceRef → GitRepository/gitops-flux-workshop
  path      → ./apps/nginx/overlays/dev
  build     → apps/nginx/overlays/dev/kustomization.yaml
  apply     → nginx-dev resources
```

A Flux `Kustomization` adds source selection, continuous reconciliation,
readiness, dependencies, decryption, retries and pruning. A Kustomize
`kustomization.yaml` only describes manifest rendering.

## Flux `Kustomization` fields

The workshop uses four Flux `Kustomization` resources:

| Name | Artifact path | Dependency | SOPS |
| --- | --- | --- | --- |
| `dev-namespaces` | `./infrastructure/namespaces/dev` | none | no |
| `dev-nginx` | `./apps/nginx/overlays/dev` | `dev-namespaces` | yes |
| `prod-namespaces` | `./infrastructure/namespaces/prod` | none | no |
| `prod-nginx` | `./apps/nginx/overlays/prod` | `prod-namespaces` | yes |

Every field used by these resources:

* `apiVersion: kustomize.toolkit.fluxcd.io/v1`
  * selects the stable Flux Kustomize API
* `kind: Kustomization`
  * identifies the Flux reconciliation resource
* `metadata.name`
  * identifies one reconciliation pipeline
* `metadata.namespace: flux-system`
  * places the object beside its source and decryption Secret
* `spec.interval: 1m`
  * schedules successful reconciliation approximately every minute
  * a source revision event can trigger reconciliation before the interval
* `spec.retryInterval: 20s`
  * schedules another attempt after apply, build or readiness failure
  * it does not replace the normal successful interval
* `spec.timeout: 2m`
  * limits build, apply and health-check operations in one attempt
* `spec.path`
  * selects a directory inside the referenced artifact
* `spec.prune: true`
  * removes previously managed objects that leave the desired state
* `spec.wait: true`
  * checks all reconciled resources for readiness
  * when enabled, an explicit `healthChecks` list would be ignored
* `spec.sourceRef.kind` and `spec.sourceRef.name`
  * select the source artifact
* `spec.dependsOn[].name`
  * blocks nginx until its namespace `Kustomization` is `Ready=True`
* `spec.decryption.provider: sops`
  * enables SOPS decryption
* `spec.decryption.secretRef.name: sops-age`
  * selects the Secret containing the age identity

Fields such as `targetNamespace`, `force`, `healthChecks`, `suspend` and
`serviceAccountName` are not needed by these manifests and are not added merely
for demonstration.

## Reconciliation behavior

### Desired state and drift

For each successful reconciliation, `kustomize-controller`:

1. obtains the referenced artifact
2. selects `spec.path`
3. decrypts configured SOPS resources
4. runs the Kustomize build
5. validates and server-side applies the result
6. checks readiness
7. records the applied revision and managed-object inventory

A manual change to a managed field is drift. A later reconciliation applies the
Git value again.

### Readiness

`wait: true` checks every reconciled resource supported by Flux health
assessment. `dev-nginx` becomes ready only after its nginx Deployment completes
its rollout.

Readiness is reported in `.status.conditions`. It does not mean that the source
will never be checked again.

### Retries

A failed build, apply or health check makes the Flux `Kustomization` not ready.
The workshop retries after `20s`. After success, the normal `1m` interval is
used again.

### Dependencies

`dev-nginx` waits for `dev-namespaces`. `prod-nginx` waits for
`prod-namespaces`.

Dependencies order Flux pipelines, not individual YAML files. A circular
dependency never becomes ready.

### Pruning

Each Flux `Kustomization` records its own managed-object inventory.

With `prune: true`:

* an object removed from the rendered source is garbage-collected
* deleting the Flux `Kustomization` also removes its managed objects by default
* another Flux `Kustomization`'s inventory is not pruned

The nginx and namespace inventories are separate. Deleting `dev-nginx` removes
the dev workload but leaves `nginx-dev`, which belongs to `dev-namespaces`.

## Project structure

```text
.
├── .sops.yaml
├── .sourceignore
├── local-setup/
├── apps/nginx/
├── infrastructure/namespaces/
└── clusters/
```

### Root and local setup

* `.sops.yaml`
  * supplies the public age recipient when workshop Secrets are created or updated locally
  * is not the decryption key used by Flux
* `.sourceignore`
  * excludes `local-setup/` from the source artifact
* `local-setup/workshop.agekey`
  * contains the disposable private age identity
* `local-setup/kustomization.yaml`
  * generates `Secret/sops-age` in `flux-system`
  * is applied directly by the participant, not by Flux

### Nginx base

* `apps/nginx/base/deployment.yaml`
  * runs the pinned nginx image
  * mounts the environment `ConfigMap`
  * defines health probes and resource requests and limits
* `apps/nginx/base/service.yaml`
  * exposes nginx inside the cluster
* `apps/nginx/base/kustomization.yaml`
  * groups the shared Deployment and Service

The base is composition-only. Render an overlay because the environment
`ConfigMap` is supplied there.

### Nginx overlays

Both `apps/nginx/overlays/dev` and `apps/nginx/overlays/prod` contain:

* `configmap.yaml`
  * provides the environment-specific `index.html`
* `deployment-patch.yaml`
  * sets the environment replica count
* `secret.enc.yaml`
  * contains a dummy SOPS-encrypted Kubernetes Secret
* `kustomization.yaml`
  * selects the namespace, base, ConfigMap, encrypted Secret and patch

### Infrastructure

* `infrastructure/namespaces/dev/namespace.yaml`
  * defines `nginx-dev`
* `infrastructure/namespaces/dev/kustomization.yaml`
  * renders the dev namespace entry point
* `infrastructure/namespaces/prod/namespace.yaml`
  * defines `nginx-prod`
* `infrastructure/namespaces/prod/kustomization.yaml`
  * renders the prod namespace entry point

### Cluster wiring

* `clusters/source.yaml`
  * defines the one `GitRepository` used by both environments
* `clusters/kustomization.yaml`
  * groups the source and both environment directories for `kubectl apply -k clusters`

`clusters/dev`:

* `namespaces.yaml`
  * reconciles the dev namespace path
* `nginx.yaml`
  * reconciles the dev nginx overlay after `dev-namespaces`
* `kustomization.yaml`
  * groups both dev Flux resources for local application

`clusters/prod` has the same three file roles for prod.

Docker Desktop is one physical cluster. The dev and prod directories model two
logical environments in separate namespaces. In a fleet repository, a
`clusters/<name>` directory commonly represents one physical cluster.

## SOPS from Flux's perspective

The encrypted files retain plaintext Kubernetes identity fields and encrypted
`stringData` values.

At reconciliation time:

1. `source-controller` publishes the encrypted files in the artifact
2. `kustomize-controller` reads `decryption.secretRef.name`
3. it loads `identity.agekey` from `Secret/sops-age` in `flux-system`
4. it decrypts the Secret values in memory
5. it builds and applies the Kubernetes resources
6. the Kubernetes API receives a normal plaintext Secret object

The controller does not use `.sops.yaml` to decrypt an existing file. The file's
SOPS metadata records the recipients and encryption settings. `.sops.yaml` is
used by the local SOPS CLI when creating or updating encrypted files.

The dummy Secret is not consumed or exposed by nginx. It exists only to make
Flux decryption observable.

## Helm releases

`helm-controller` reconciles a `HelmRelease` custom resource.

Typical flow:

```text
HelmRepository or GitRepository
  → HelmChart artifact
  → HelmRelease
  → Helm install, upgrade, test, remediation or uninstall
```

* `source-controller` obtains repository and chart content
* `helm-controller` performs Helm release actions
* `HelmRelease` supports dependencies, health status and failure remediation
* a Flux `Kustomization` can apply a `HelmRelease` and wait for it to become ready

This workshop uses raw Kubernetes manifests because adding a chart would obscure
the source-to-Kustomize path being studied.

## Image automation

Flux image automation uses three resource stages:

```text
ImageRepository → ImagePolicy → ImageUpdateAutomation → Git commit
```

* `ImageRepository` scans image metadata from a registry
* `ImagePolicy` selects a tag according to a policy
* `ImageUpdateAutomation` changes marked YAML fields and commits the result to Git
* normal source and workload reconciliation then applies that Git revision

Image automation preserves Git as the desired-state record. It does not patch
the Deployment directly.

The two image controllers are optional. Git write-back also requires narrowly
scoped write credentials and a branch strategy. They are not installed or used
by this workshop.

## Notifications

`notification-controller` handles two directions:

* inbound
  * a `Receiver` accepts a signed webhook from systems such as GitHub
  * it requests reconciliation of selected Flux resources without waiting for polling
* outbound
  * a `Provider` defines a destination such as Slack, Teams or a generic webhook
  * an `Alert` selects event sources and severity to forward

No notification resources are applied here because they require an external
endpoint, credentials or ingress. Flux Kubernetes events remain available
without an external provider.

## Repository structures and conventions

Flux supports several repository boundaries:

* one monorepo
  * applications, infrastructure and cluster entry points share one repository
  * this workshop uses this model
* one repository per cluster
  * provides a strong cluster ownership boundary
  * shared configuration needs versioned composition or duplication control
* application repository plus configuration repository
  * separates application builds from deployment promotion and access
* one repository per team or tenant
  * supports ownership boundaries
  * creates more sources and credentials to operate

Flux does not require names such as:

* `apps`
* `infrastructure`
* `clusters`
* `base`
* `overlays`
* `dev`
* `prod`
* `source.yaml`
* `nginx.yaml`

They are repository conventions. Flux requires its custom resources, valid
references and valid artifact-relative paths.

## Security

* protect Git writes with review, branch protection and least privilege
* use read-only source credentials unless a controller must write to Git
* restrict image automation write access to its intended branch and files
* verify Git signatures when provenance requirements justify it
* keep SOPS private identities and KMS credentials outside Git
* give each tenant separate sources, keys and namespaces
* use `spec.serviceAccountName` so reconcilers impersonate a restricted service account
* disable cross-namespace references in multi-tenant installations when they are unnecessary
* restrict controller egress to required Git, registry, KMS and notification endpoints
* use admission policy for resource kinds and security requirements
* pin production images by immutable digest
* review pruning ownership before enabling deletion

Default installations prioritize operator convenience. Shared clusters require
explicit RBAC and multi-tenancy hardening.

## Workshop

### Prerequisites

* Docker Desktop is running
* Docker Desktop Kubernetes is enabled
* `kubectl`, Flux CLI and SOPS are installed
* this repository is committed and reachable on branch `main`

Verify the client and context:

```bash
kubectl version --client
flux --version
sops --version
kubectl config current-context
```

Expected context:

```text
docker-desktop
```

Check cluster prerequisites:

```bash
flux check --pre
```

Expected result: the Kubernetes version and prerequisites pass.

### 1. Install Flux

```bash
flux install
kubectl -n flux-system get deployments
```

Expected deployments:

```text
source-controller
kustomize-controller
helm-controller
notification-controller
```

Wait until they are available:

```bash
kubectl -n flux-system wait deployment --all \
  --for=condition=Available \
  --timeout=2m
```

### 2. Apply the age identity

```bash
kubectl apply -k local-setup
kubectl -n flux-system get secret sops-age
```

Expected result: `Secret/sops-age` exists with one data entry.

### 3. Connect Flux to Git

The committed source points to the public workshop repository. To use a fork,
replace `spec.url` in `clusters/source.yaml` with the fork URL and push that
change before continuing.

Apply the source and reconciliation resources:

```bash
kubectl apply -k clusters
flux reconcile source git gitops-flux-workshop
```

Expected result: source reconciliation succeeds for a `main@sha1:<commit>`
revision.

Inspect the artifact:

```bash
kubectl -n flux-system get gitrepository gitops-flux-workshop \
  -o jsonpath='{.status.artifact.revision}{"\n"}{.status.artifact.digest}{"\n"}{.status.artifact.url}{"\n"}'
```

Expected result: revision, SHA-256 digest and an in-cluster artifact URL are
reported.

### 4. Reconcile both environments

```bash
flux reconcile kustomization dev-namespaces
flux reconcile kustomization dev-nginx
flux reconcile kustomization prod-namespaces
flux reconcile kustomization prod-nginx
flux get kustomizations
```

Expected result: all four Flux `Kustomization` resources are `Ready=True` at the
same Git revision.

Verify the workloads:

```bash
kubectl -n nginx-dev get deployment,service,configmap,secret
kubectl -n nginx-prod get deployment,service,configmap,secret
```

Expected result:

* dev has one ready nginx replica
* prod has two ready nginx replicas
* both namespaces contain `nginx-index` and `nginx-workshop-secret`

### 5. Read the environment pages

Start a dev port-forward:

```bash
kubectl -n nginx-dev port-forward service/nginx 8080:80
```

In another terminal:

```bash
curl --silent http://localhost:8080
```

Expected content:

```text
environment: dev
```

Stop the port-forward. Repeat for prod:

```bash
kubectl -n nginx-prod port-forward service/nginx 8080:80
```

Expected content from `curl --silent http://localhost:8080`:

```text
environment: prod
```

### 6. Verify Flux decryption

Read the environment marker from the applied dev Secret:

```bash
kubectl -n nginx-dev get secret nginx-workshop-secret \
  -o jsonpath='{.data.environment}' | base64 --decode
echo
```

Expected result:

```text
dev
```

Git still contains `ENC[AES256_GCM,...]` values. The plaintext exists in the
Kubernetes Secret because `kustomize-controller` decrypted it before apply.

### 7. Observe a Git change

This exercise requires a writable fork configured in `clusters/source.yaml`.

Change the dev page:

```bash
perl -pi -e 's/environment: dev/environment: dev-updated/' \
  apps/nginx/overlays/dev/configmap.yaml
git add apps/nginx/overlays/dev/configmap.yaml
git commit -m 'Update dev page'
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
```

Port-forward dev again and run `curl --silent http://localhost:8080`.

Expected content:

```text
environment: dev-updated
```

Restore the original content:

```bash
git revert --no-edit HEAD
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
```

### 8. Observe drift correction

Create live drift:

```bash
kubectl -n nginx-dev scale deployment nginx --replicas=4
kubectl -n nginx-dev get deployment nginx
```

Expected result: the desired replica count is temporarily four.

Request reconciliation:

```bash
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get deployment nginx
```

Expected result: the desired replica count returns to one, as declared in Git.

### 9. Observe failure, retries and dependencies

Break the namespace pipeline's artifact path:

```bash
kubectl -n flux-system patch kustomization dev-namespaces \
  --type=merge \
  --patch='{"spec":{"path":"./does-not-exist"}}'
flux reconcile kustomization dev-namespaces
```

Expected result: reconciliation reports a build failure and
`dev-namespaces` becomes `Ready=False`.

Inspect the failure:

```bash
flux get kustomizations
flux events --for Kustomization/dev-namespaces
```

The controller retries after approximately `20s`. Reconcile the dependent
workload while the dependency is not ready:

```bash
flux reconcile kustomization dev-nginx
```

Expected result: `dev-nginx` reports that dependency `dev-namespaces` is not
ready.

Restore the committed specification:

```bash
kubectl apply -f clusters/dev/namespaces.yaml
flux reconcile kustomization dev-namespaces
flux reconcile kustomization dev-nginx
```

Expected result: both dev pipelines return to `Ready=True`.

### 10. Observe pruning

Delete only the dev workload pipeline:

```bash
kubectl -n flux-system delete kustomization dev-nginx
kubectl -n nginx-dev wait deployment/nginx \
  --for=delete \
  --timeout=2m
kubectl get namespace nginx-dev
```

Expected result:

* the nginx Deployment, Service, ConfigMap and Secret are pruned
* namespace `nginx-dev` remains because another Flux `Kustomization` manages it

Restore the workload pipeline:

```bash
kubectl apply -f clusters/dev/nginx.yaml
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get deployment nginx
```

Expected result: the dev workload is recreated and ready.

## Troubleshooting

Start with the resource that owns the failed stage:

```bash
flux check
flux get sources git
flux get kustomizations
flux events --for GitRepository/gitops-flux-workshop
flux events --for Kustomization/dev-nginx
flux logs --kind=Kustomization --name=dev-nginx
kubectl -n flux-system describe gitrepository gitops-flux-workshop
kubectl -n flux-system describe kustomization dev-nginx
```

Common failures:

| Symptom | Check |
| --- | --- |
| source not ready | URL, branch, credentials, network and `.status.conditions` |
| source ready at old revision | pushed branch, artifact revision and forced source reconcile |
| build failure | artifact-relative `spec.path` and selected `kustomization.yaml` |
| dependency not ready | dependency name, namespace and `Ready` condition |
| readiness timeout | Deployment rollout, Pods, events, probes and image pull |
| SOPS failure | `sops-age` Secret name, `identity.agekey`, recipient and SOPS MAC |
| drift remains | suspended reconciliation, source revision and field ownership |
| unexpected deletion | `prune`, Kustomization inventory and prune-disable annotations |

Inspect the managed tree:

```bash
flux tree kustomization dev-nginx
```

Controller logs should be filtered by object before reading broad namespace
logs. Status conditions and events usually contain the first actionable error.

## Cleanup

Delete the Flux resources and wait for pruning:

```bash
kubectl delete -k clusters
kubectl wait namespace/nginx-dev --for=delete --timeout=2m
kubectl wait namespace/nginx-prod --for=delete --timeout=2m
kubectl delete -k local-setup
```

Expected result: both nginx environments, the workshop source and the age
identity are removed. Flux remains installed.

On a dedicated disposable cluster, Flux itself can also be removed:

```bash
flux uninstall --namespace=flux-system
```

Do not run `flux uninstall` on a cluster where Flux manages other workloads.
