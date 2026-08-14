# gitops-flux-workshop

## References

* [Flux concepts](https://fluxcd.io/flux/concepts/)
* [Flux installation](https://fluxcd.io/flux/installation/)
* [Flux components](https://fluxcd.io/flux/components/)
* [`GitRepository`](https://fluxcd.io/flux/components/source/gitrepositories/)
* [Flux `Kustomization`](https://fluxcd.io/flux/components/kustomize/kustomizations/)
* [Helm controller](https://fluxcd.io/flux/components/helm/)
* [Image automation controllers](https://fluxcd.io/flux/components/image/)
* [Notification controller](https://fluxcd.io/flux/components/notification/)
* [Repository structures](https://fluxcd.io/flux/guides/repository-structure/)
* [SOPS decryption](https://fluxcd.io/flux/guides/mozilla-sops/)
* [Flux security](https://fluxcd.io/flux/security/)
* [Argo CD workshop](https://github.com/mtumilowicz/argoCD-workshop#readme)
* [Argo CD overview](https://argo-cd.readthedocs.io/en/stable/)
* [Argo CD architecture](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
* [Argo CD Helm support](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)

## Workshop

* purpose
  * demonstrates pull-based GitOps with Flux on Docker Desktop Kubernetes
  * deploys the same nginx base to two namespaces
* environments
  * dev
    * namespace: `nginx-dev`
    * replicas: 1
    * page: `environment: dev`
  * prod
    * namespace: `nginx-prod`
    * replicas: 2
    * page: `environment: prod`
* application
  * each overlay provides its page through a `ConfigMap`
  * there is no application project or image build
* prerequisite knowledge
  * Kustomize bases, overlays and patches from `kustomize-workshop`
  * SOPS recipients, identities and encrypted YAML from `sops-age-key-workshop`
* scope
  * covers only the Flux-specific use of those tools

### Warning

* [`local-setup/workshop.agekey`](./local-setup/workshop.agekey)
  * disposable private identity committed for reproducibility
  * provides no confidentiality
* production private identities
  * must be delivered outside Git

## GitOps and Flux

* shared GitOps concepts
  * for Git as the source of truth, desired and live state, pull-based delivery
    and drift, see [GitOps in the Argo CD workshop](https://github.com/mtumilowicz/argoCD-workshop#gitops)
* Flux implementation
  * keeps reviewed desired state in Git
  * runs controllers inside the target environment
  * pulls desired state and continuously reconciles it with the live system
* flow

```text
developer → commit and push → Git
                              ↓ pull
                         Flux controllers
                              ↓ apply
                         Kubernetes API
```

* push-pipeline difference
  * CI holds cluster credentials
  * CI runs commands such as `kubectl apply` after a build
* Flux reconciliation
  * convergence
    * live resources are moved toward the selected Git revision
  * drift correction
    * managed fields changed manually are restored
  * deletion
    * resources removed from desired state can be pruned
  * auditability
    * Git records who proposed and approved a change
  * recovery
    * a previous desired state can be restored with another Git commit
* state
  * Git records desired state
  * Kubernetes status records current health and observed state

## Architecture and controllers

* architecture
  * toolkit of specialized Kubernetes controllers
  * controllers communicate through custom resources, status, artifacts and events
* controllers
  * `source-controller`
    * watches: `GitRepository`, `OCIRepository`, `HelmRepository`, `HelmChart`, `Bucket`
    * fetches sources and publishes versioned artifacts
  * `kustomize-controller`
    * watches: Flux `Kustomization`
    * decrypts, builds, validates, applies, checks and prunes manifests
  * `helm-controller`
    * watches: `HelmRelease`
    * performs Helm install, upgrade, test, remediation and uninstall operations
  * `notification-controller`
    * watches: `Receiver`, `Provider`, `Alert`
    * handles inbound webhooks and outbound events
  * `image-reflector-controller`
    * watches: `ImageRepository`, `ImagePolicy`
    * scans registries and selects image versions
  * `image-automation-controller`
    * watches: `ImageUpdateAutomation`
    * updates marked YAML and commits changes to Git
* installation defaults
  * the first four controllers are installed by default
  * the image controllers are optional
* workshop reconciliation path

```text
Git commit
  → GitRepository
  → source-controller artifact
  → Flux Kustomization
  → path inside the artifact
  → SOPS decryption
  → Kustomize build
  → server-side apply
  → readiness and inventory
```

* reconciliation triggers
  * a new source artifact emits an event
  * referencing controllers can reconcile before their normal interval expires
  * a `Receiver` webhook can request source reconciliation sooner than polling

## Installation versus bootstrap

### Installation

* workshop command

```bash
flux install
```

* result
  * installs Flux CRDs, controllers, RBAC and network policies
  * does not connect the cluster to this repository
  * does not store the installation manifests in Git
  * the workshop creates the source and reconciliation objects explicitly
* use
  * `flux install` is intended for development and testing
  * current Flux guidance recommends bootstrap for long-lived installations

### Bootstrap

* corresponding GitHub command

```bash
flux bootstrap github \
  --owner=mtumilowicz \
  --repository=gitops-flux-workshop \
  --branch=main \
  --path=clusters \
  --personal
```

* workshop restriction
  * do not run this command during the workshop
  * it would modify the repository
* behavior
  * installs or upgrades Flux
  * configures Git authentication
  * commits controller and synchronization manifests
  * creates a `GitRepository` and root Flux `Kustomization`
  * makes Flux manage its own installation from Git
  * is idempotent
* generated `flux-system` directory
  * `gotk-components.yaml`
    * Flux CRDs, controllers, RBAC and supporting resources
  * `gotk-sync.yaml`
    * bootstrap `GitRepository` and Flux `Kustomization`
  * `kustomization.yaml`
    * Kustomize entry point for both files
* selection
  * use installation for an isolated experiment
  * use bootstrap when the cluster should be reproducible and Flux upgrades
    should also follow Git

## Repository structure

* layout

```text
.
├── .gitignore                                  # ignores local IDE and OS files
├── .sops.yaml                                  # local encryption policy and public age recipient
├── .sourceignore                               # excludes local-setup from the source artifact
├── README.md                                   # workshop guide
├── local-setup/
│   ├── kustomization.yaml                      # generates Secret/sops-age in flux-system
│   └── workshop.agekey                         # disposable private age identity
├── apps/nginx/
│   ├── base/
│   │   ├── deployment.yaml                     # shared nginx Deployment
│   │   ├── service.yaml                        # shared nginx Service
│   │   └── kustomization.yaml                  # shared Kustomize entry point
│   └── overlays/
│       ├── dev/
│       │   ├── configmap.yaml                  # dev index.html
│       │   ├── deployment-patch.yaml           # one replica
│       │   ├── secret.enc.yaml                 # encrypted dummy dev Secret
│       │   └── kustomization.yaml              # renders the dev workload
│       └── prod/
│           ├── configmap.yaml                  # prod index.html
│           ├── deployment-patch.yaml           # two replicas
│           ├── secret.enc.yaml                 # encrypted dummy prod Secret
│           └── kustomization.yaml              # renders the prod workload
├── infrastructure/namespaces/
│   ├── dev/
│   │   ├── namespace.yaml                      # Namespace/nginx-dev
│   │   └── kustomization.yaml                  # renders the dev namespace
│   └── prod/
│       ├── namespace.yaml                      # Namespace/nginx-prod
│       └── kustomization.yaml                  # renders the prod namespace
└── clusters/
    ├── source.yaml                             # shared GitRepository
    ├── kustomization.yaml                      # local entry point for all Flux objects
    ├── dev/
    │   ├── namespaces.yaml                     # Flux Kustomization for the dev namespace
    │   ├── nginx.yaml                          # Flux Kustomization for the dev workload
    │   └── kustomization.yaml                  # groups both dev Flux objects
    └── prod/
        ├── namespaces.yaml                     # Flux Kustomization for the prod namespace
        ├── nginx.yaml                          # Flux Kustomization for the prod workload
        └── kustomization.yaml                  # groups both prod Flux objects
```

* environment model
  * Docker Desktop supplies one physical cluster
  * `dev` and `prod` are logical environments in separate namespaces
* directory names
  * `apps`, `infrastructure`, `clusters`, `base`, `overlays`, `dev` and `prod`
    are conventions
  * Flux requires valid API objects, references and artifact paths
  * Flux does not require these names
* common repository structures
  * monorepo
    * applications, infrastructure and environments in one repository
  * repository per cluster
    * strong cluster ownership
    * more shared-content coordination
  * application source plus deployment repository
    * separates builds from promotion
  * repository per team
    * clear ownership
    * more sources and credentials to operate
* workshop selection
  * uses a monorepo
  * one commit can show the complete source, environment and reconciliation
    relationship

## `GitRepository` and source artifacts

[`clusters/source.yaml`](./clusters/source.yaml) defines one source for both
environments:

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

Every field used:

* `apiVersion` selects the stable Source API
* `kind` selects the `GitRepository` resource
* `metadata.name` identifies the source
* `metadata.namespace` determines its namespace and reference scope
* `spec.interval` schedules Git checks
* `spec.url` identifies the remote repository
* `spec.ref.branch` resolves the tip of `main`

For a successful reconciliation, `source-controller`:

1. resolves the configured reference to a commit
2. applies default exclusions and `.sourceignore`
3. archives the remaining content
4. publishes the artifact inside the cluster
5. reports revision, digest, size and URL in `.status.artifact`

The revision identifies the Git input. The digest identifies the produced
artifact content. They are different because files may be excluded.

## Flux `Kustomization`

[`clusters/dev/nginx.yaml`](./clusters/dev/nginx.yaml) defines the dev
reconciliation pipeline:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev-nginx
  namespace: flux-system
spec:
  interval: 1m
  retryInterval: 20s
  timeout: 2m
  path: ./apps/nginx/overlays/dev
  prune: true
  wait: true
  sourceRef:
    kind: GitRepository
    name: gitops-flux-workshop
  dependsOn:
    - name: dev-namespaces
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```

Every field used:

* `apiVersion` selects the stable Flux Kustomize API
* `kind` selects the Flux `Kustomization` resource
* `metadata.name` identifies this pipeline
* `metadata.namespace` places it in `flux-system`
* `spec.interval` schedules successful reconciliation approximately every minute
* `spec.retryInterval` retries failures after 20 seconds
* `spec.timeout` limits build, apply and health-check operations to two minutes
* `spec.path` selects a directory in the source artifact
* `spec.prune` enables deletion of objects removed from desired state
* `spec.wait` checks all reconciled resources for readiness
* `spec.sourceRef.kind` selects the source type
* `spec.sourceRef.name` selects `GitRepository/gitops-flux-workshop`
* `spec.dependsOn[].name` waits for `dev-namespaces` to be ready
* `spec.decryption.provider` enables SOPS
* `spec.decryption.secretRef.name` selects `Secret/sops-age`

`sourceRef.namespace` is omitted. Flux therefore looks for the source in the
Flux `Kustomization` namespace, `flux-system`.

### Artifact-relative path

`spec.path` starts at the artifact root, not beside `clusters/dev/nginx.yaml`:

```text
GitRepository artifact
└── apps/nginx/overlays/dev
    └── kustomization.yaml
```

`./apps/nginx/overlays/dev` is valid. `./overlays/dev` is not.

### Flux `Kustomization` versus Kustomize

| Flux `Kustomization` | Kustomize `kustomization.yaml` |
| --- | --- |
| Kubernetes custom resource | Kustomize build instructions |
| read by `kustomize-controller` | read by Kustomize |
| selects a source artifact and path | selects resources, generators and patches |
| reconciles continuously | renders once per invocation |
| supports readiness, retry, dependency, decryption and pruning | does not manage runtime state |

The relationship is:

```text
clusters/dev/nginx.yaml
  → sourceRef: GitRepository/gitops-flux-workshop
  → path: apps/nginx/overlays/dev
  → apps/nginx/overlays/dev/kustomization.yaml
  → nginx-dev resources
```

### How the dev overlay is built

Kustomize does not automatically load every YAML file in a directory. A
`resources` list explicitly defines the files and Kustomize directories that
participate in the build.

The dev overlay starts with:

```yaml
resources:
  - ../../base
  - configmap.yaml
  - secret.enc.yaml
```

The process is:

1. Kustomize follows `../../base` and opens
   `apps/nginx/base/kustomization.yaml`.
2. The base registers `deployment.yaml` and `service.yaml` under `resources`.
3. Kustomize loads the objects declared in those files:
   `Deployment/nginx` and `Service/nginx`.
4. Kustomize returns to the dev overlay and loads `ConfigMap/nginx-index` and
   `Secret/nginx-workshop-secret`.
5. The overlay registers `deployment-patch.yaml` under `patches`.
6. Kustomize reads the patch identity:

   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: nginx
   ```

7. Kustomize finds the loaded resource with the same API version, kind and
   name: `apps/v1 Deployment/nginx`.
8. It merges `spec.replicas: 1` into that Deployment. Other Deployments are not
   selected.
9. It assigns `nginx-dev` to namespaced resources and renders the final YAML.

Filenames do not identify Kubernetes resources. `deployment.yaml` and
`deployment-patch.yaml` could be renamed if their `kustomization.yaml`
references were updated. Patch matching comes from `apiVersion`, `kind` and
`metadata.name` inside the YAML.

## Reconciliation behavior

* reconciliation
  * runs after a relevant source revision event or the configured interval
  * applies desired fields with server-side apply
* drift correction
  * a manual change to a managed field is replaced by the Git value
* readiness
  * `wait: true` assesses all supported objects in the rendered output
  * `dev-nginx` becomes ready after the nginx Deployment rollout succeeds
* timeout
  * one build, apply and health-check attempt may run for at most two minutes
* retry
  * a failed attempt is retried after 20 seconds
  * successful reconciliation returns to the one-minute interval
* dependency
  * `dev-nginx` waits for `dev-namespaces`
  * `prod-nginx` waits for `prod-namespaces`
  * dependencies order pipelines, not individual YAML files
  * circular dependencies never become ready
* inventory
  * each Flux `Kustomization` records the objects it owns in `.status.inventory`
* pruning
  * with `prune: true`, an owned object removed from desired state is deleted
  * deleting the Flux `Kustomization` also deletes its inventory by default
  * one pipeline does not prune another pipeline's inventory

The namespace and workload pipelines are separate. Pruning `dev-nginx` does not
remove `nginx-dev`, which belongs to `dev-namespaces`.

## SOPS decryption

Flux receives the encrypted files through the source artifact. At
reconciliation time, `kustomize-controller`:

1. reads `decryption.secretRef.name`
2. loads `identity.agekey` from `Secret/sops-age` in `flux-system`
3. decrypts the encrypted values in memory
4. builds and applies a normal Kubernetes Secret

`.sops.yaml` supplies the public recipient when the local SOPS CLI creates or
updates a file. Flux does not use it to decrypt an existing file. Decryption
uses the encrypted file metadata and the private identity in the Kubernetes
Secret.

SOPS protects secret values stored in Git. It does not authorize a deployment,
protect plaintext already stored in Kubernetes or prove that a Git change is
safe.

## Helm, image automation and notifications

### HelmRelease

```text
HelmRepository or GitRepository
  → HelmChart artifact
  → HelmRelease
  → Helm install, upgrade, test, remediation or uninstall
```

`helm-controller` watches `HelmRelease`, creates or references the required
`HelmChart`, obtains the artifact from `source-controller` and performs Helm
release operations. A Flux `Kustomization` can apply a `HelmRelease` and wait
for it to become ready.

The workshop uses Kubernetes manifests because its purpose is to expose the
`GitRepository` to Kustomize reconciliation path.

### Image automation

```text
ImageRepository → ImagePolicy → ImageUpdateAutomation → Git commit
                                                        ↓
                                              normal Flux reconciliation
```

`image-reflector-controller` scans a registry and evaluates the policy.
`image-automation-controller` updates marked YAML fields and commits the change
to Git. It does not patch the Deployment directly.

Image automation requires the optional controllers, registry access and
narrowly scoped Git write credentials. Those dependencies are outside this
workshop.

### Notifications

Inbound flow:

```text
Git provider webhook → Receiver → requested source reconciliation
```

Outbound flow:

```text
Flux event → Alert filter → Provider → Slack, Teams, webhook or another service
```

No notification objects are included because a runnable example requires an
external endpoint, credentials and, for inbound webhooks, network exposure.
Kubernetes events and controller logs remain available locally.

## Flux versus Argo CD

Both implement pull-based continuous delivery for Kubernetes. Their operating
models differ.

| Area | Flux | Argo CD |
| --- | --- | --- |
| Primary abstraction | sources plus specialized reconciliation resources | `Application`, `ApplicationSet` and `AppProject` |
| Architecture | composable Kubernetes controllers | application controller, repository server, API server and integrated UI |
| Built-in interface | Kubernetes API and Flux CLI | Kubernetes API, Argo CD API, CLI and web UI |
| Installation lifecycle | bootstrap can make Flux manage itself from Git | installation followed by declarative application configuration |
| Multi-cluster style | commonly installed per cluster; remote reconciliation is also supported | commonly centralizes registered clusters in one control plane |
| Kustomize | reconciled by `kustomize-controller` | rendered by the repository server for an `Application` |
| Helm | `HelmRelease` manages Helm release operations | Helm renders manifests; Argo CD manages application lifecycle |
| SOPS | native decryption in `kustomize-controller` | normally requires a plugin or separate secret solution |
| Image updates | official optional Flux image controllers write to Git | normally uses the separate Argo CD Image Updater or another tool |
| Notifications | `Receiver`, `Alert` and `Provider` APIs | integrated Argo CD Notifications |
| Tenancy | Kubernetes RBAC, namespaces and service-account impersonation | Argo CD RBAC and `AppProject` source, destination and resource restrictions |
| Visual operations | no built-in Flux web UI | built-in application topology, health, diff and synchronization UI |

Choose Flux when:

* Kubernetes-native APIs and controller composition are preferred
* GitOps bootstrap and self-management are important
* native SOPS decryption is required
* image selection and Git write-back should use official Flux controllers
* teams prefer Kubernetes RBAC and CLI-driven operation
* explicit dependencies between reconciliation pipelines are useful

Choose Argo CD when:

* a central application inventory and web interface are primary requirements
* operators need visual health, diffs, history and synchronization controls
* `ApplicationSet` should generate applications across clusters or repositories
* `AppProject` is a good fit for application-level tenancy and policy
* a central control plane managing registered clusters matches the operating model

Neither is universally better. Decide using the required interface, cluster
topology, tenancy boundary, secret workflow, Helm semantics, Git write-back and
the team's operational experience.

## Security

* Git trust
  * repository write access can change cluster resources
  * require review, branch protection and narrowly scoped credentials
  * use Git signature verification where commit provenance is required
* reconciliation authorization
  * default installations favor convenience
  * use `spec.serviceAccountName` and restricted RBAC for tenant workloads
  * disable unnecessary cross-namespace references on shared clusters
* secrets
  * keep private SOPS identities and KMS credentials outside Git
  * use separate keys and namespaces for separate trust boundaries
* images
  * use immutable digests for production provenance
  * restrict registry access and image-automation Git writes
* network
  * restrict controller egress to required Git, registry, KMS and notification endpoints
* deletion
  * verify inventory ownership before enabling pruning
  * protect resources that require an explicit retention policy

## Exercises

Prerequisites: Docker Desktop Kubernetes, `kubectl`, Flux CLI, SOPS and this
repository committed to a reachable `main` branch.

### 1. Verify prerequisites

```bash
kubectl config current-context
flux check --pre
```

Expected: context `docker-desktop` and `prerequisites checks passed`.

### 2. Install Flux

```bash
flux install
kubectl -n flux-system wait deployment --all \
  --for=condition=Available \
  --timeout=2m
kubectl -n flux-system get deployments
```

Expected: the four default controllers are available in `flux-system`.

### 3. Provide the age identity

```bash
kubectl apply -k local-setup
kubectl -n flux-system get secret sops-age
```

Expected: `Secret/sops-age` is `Opaque` and contains one data entry.

### 4. Connect the source

When using a fork, change `spec.url` in `clusters/source.yaml`, commit and push
before continuing.

```bash
kubectl apply -k clusters
flux reconcile source git gitops-flux-workshop
```

Expected: status contains `stored artifact for revision 'main@sha1:<commit>'`.

Inspect the artifact:

```bash
kubectl -n flux-system get gitrepository gitops-flux-workshop \
  -o jsonpath='{.status.artifact.revision}{"\n"}{.status.artifact.digest}{"\n"}{.status.artifact.url}{"\n"}'
```

Expected: a `main@sha1:` revision, `sha256:` digest and internal artifact URL.

### 5. Reconcile dev and prod

```bash
flux reconcile kustomization dev-namespaces
flux reconcile kustomization dev-nginx
flux reconcile kustomization prod-namespaces
flux reconcile kustomization prod-nginx
flux get kustomizations
```

Expected: all four resources report `Ready=True` at the selected revision.

Verify the replica counts:

```bash
kubectl -n nginx-dev get deployment nginx
kubectl -n nginx-prod get deployment nginx
```

Expected: dev reports `1/1`; prod reports `2/2`.

### 6. Read both pages

```bash
kubectl -n nginx-dev port-forward service/nginx 8080:80
```

From another terminal:

```bash
curl --silent http://localhost:8080
```

Expected: `environment: dev`. Stop it and repeat with `-n nginx-prod`;
expected: `environment: prod`.

### 7. Verify Flux decryption

```bash
kubectl -n nginx-dev get secret nginx-workshop-secret \
  -o jsonpath='{.data.environment}' | base64 --decode
echo
```

Expected: `dev`. Git contains ciphertext; Kubernetes contains the Secret
produced after in-memory decryption.

### 8. Observe a Git change

This exercise requires a writable remote configured in `clusters/source.yaml`.

```bash
perl -pi -e 's/environment: dev/environment: dev-updated/' \
  apps/nginx/overlays/dev/configmap.yaml
git add apps/nginx/overlays/dev/configmap.yaml
git commit -m 'Update dev page'
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
```

With the dev port-forward running, allow for projected ConfigMap propagation:

```bash
until curl --silent http://localhost:8080 | grep -q 'environment: dev-updated'; do
  sleep 2
done
```

Restore the original Git state:

```bash
git revert --no-edit HEAD
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
```

### 9. Observe drift correction

```bash
kubectl -n nginx-dev scale deployment nginx --replicas=4
kubectl -n nginx-dev get deployment nginx
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get deployment nginx
```

Expected: the desired count changes to four, then returns to the Git value one.

### 10. Observe failure, retry and dependency blocking

```bash
kubectl -n flux-system patch kustomization dev-namespaces \
  --type=merge \
  --patch='{"spec":{"path":"./does-not-exist"}}'
flux reconcile kustomization dev-namespaces
```

The command fails. Observe the 20-second retries:

```bash
kubectl -n flux-system get kustomization dev-namespaces --watch
```

```bash
flux events --for Kustomization/dev-namespaces
flux reconcile kustomization dev-nginx
```

Expected: `dev-namespaces` is `Ready=False`; `dev-nginx` reports that its
dependency is not ready.

Restore the committed object:

```bash
kubectl apply -f clusters/dev/namespaces.yaml
flux reconcile kustomization dev-namespaces
flux reconcile kustomization dev-nginx
```

Expected: both dev pipelines return to `Ready=True`.

### 11. Observe pruning from Git

Remove `secret.enc.yaml` from the `resources` list in
`apps/nginx/overlays/dev/kustomization.yaml`, then commit and push:

```bash
git add apps/nginx/overlays/dev/kustomization.yaml
git commit -m 'Remove dev workshop secret'
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get secret nginx-workshop-secret
```

Expected: Kubernetes reports `NotFound`; pruning removed the owned Secret.

Restore it through Git:

```bash
git revert --no-edit HEAD
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get secret nginx-workshop-secret
```

Expected: the Secret exists again.

## Troubleshooting

Follow the failed stage from source to workload:

```bash
flux check
flux get sources git
flux get kustomizations
flux events --for GitRepository/gitops-flux-workshop
flux events --for Kustomization/dev-nginx
flux logs --kind=Kustomization --name=dev-nginx
flux tree kustomization dev-nginx
kubectl -n nginx-dev get pods
kubectl -n nginx-dev describe deployment nginx
```

| Symptom | Check |
| --- | --- |
| source not ready | URL, branch, credentials, network and source conditions |
| old revision | pushed branch, artifact revision and source reconciliation |
| build failure | artifact-relative `spec.path` and selected Kustomize file |
| dependency failure | dependency name and `Ready` condition |
| readiness timeout | Pods, events, image pull and probes |
| SOPS failure | `sops-age`, `identity.agekey`, recipient and MAC |
| persistent drift | suspension, source revision and field ownership |
| unexpected deletion | pruning configuration and object inventory |

Status conditions and object-scoped events normally contain the first
actionable error.

## Cleanup

```bash
kubectl delete -k clusters
kubectl wait namespace/nginx-dev --for=delete --timeout=2m
kubectl wait namespace/nginx-prod --for=delete --timeout=2m
kubectl delete -k local-setup
```

Expected: the workshop source, reconciliation objects, namespaces and age
identity are removed. Flux remains installed.

On a dedicated disposable cluster only:

```bash
flux uninstall --namespace=flux-system
```

Do not uninstall Flux from a cluster where it manages other workloads.
