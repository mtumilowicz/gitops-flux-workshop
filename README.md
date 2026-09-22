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
* [Flux security](https://fluxcd.io/flux/security/)
* [Kubernetes workshop](https://github.com/mtumilowicz/kubernetes-workshop#readme)
* [Kubernetes objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
* [Kubernetes controllers](https://kubernetes.io/docs/concepts/architecture/controller/)
* [Kubernetes custom resources](https://kubernetes.io/docs/concepts/extend-kubernetes/api-extension/custom-resources/)
* [Argo CD workshop](https://github.com/mtumilowicz/argoCD-workshop#readme)
* [Argo CD overview](https://argo-cd.readthedocs.io/en/stable/)
* [Argo CD architecture](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)
* [Argo CD Helm support](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)

## Workshop

* purpose
  * demonstrates pull-based GitOps with Flux on Docker Desktop Kubernetes
* prerequisite knowledge
  * Kubernetes API server, resources, desired state, built-in controllers,
    namespaces, Deployments, Services and ConfigMaps from:
    https://github.com/mtumilowicz/kubernetes-workshop

## GitOps and Flux

* for Git as the source of truth, desired and live state, pull-based delivery
  and drift, see [GitOps in the Argo CD workshop](https://github.com/mtumilowicz/argoCD-workshop#gitops)
    * refresher
        ```text
        developer → commit and push → Git
                                      ↓ pull
                                 Flux controllers
                                      ↓ apply
                                 Kubernetes API
        ```
* Flux - pulls desired state and continuously reconciles it with the live system
* vs push pipeline

  | Aspect | Push pipeline | Flux |
  |---|---|---|
  | Execution | Runs a deployment command once, then stops. | Runs continuously inside the cluster. |
  | Direction | Pushes changes from CI to Kubernetes. | Pulls desired state from Git. |
  | Credentials | Requires CI to hold Kubernetes credentials. | Uses its in-cluster Kubernetes identity. |
  | Drift | Does not detect changes made after deployment. | Regularly detects and corrects drift. |
  | Retries | Requires a pipeline retry or another run. | Continues retrying failed reconciliation. |
  | Audit records | Can retain Git history, approvals, CI logs, deployment records, and Kubernetes audit logs. | Adds reconciliation status, events, and controller logs to the same Git history. |

* Flux reconciliation
  * Kubernetes refresher
    * a controller watches API objects for changes and also reconciles them on a
      timer or retry
    * during reconciliation, the controller reads the latest desired state,
      inspects the current state, performs required changes and reports the result
  * convergence
    * creates or updates resources until the cluster matches Git
  * drift correction
    * changes done manually are restored
  * pruning
    * when `spec.prune: true`, Flux deletes managed objects removed from the
      desired state
  * dependency graphs
    * within one Flux `Kustomization`, Flux applies CRDs and Namespaces before
      resources that require them
    * between Flux `Kustomization` objects, `spec.dependsOn` defines explicit
      readiness dependencies
* recovery through Git history
  * restore a previous desired state with a new commit that reverts the change

## Kubernetes API model used by Flux

* core idea
  * Flux uses the Kubernetes API for configuration and controller coordination
  * installing Flux adds custom resource types such as `GitRepository`,
    `Kustomization` and `HelmRelease`
  * the Kubernetes API server stores objects of those types alongside built-in
    objects such as `Deployment` and `Service`
  * Flux controllers watch the custom objects and perform the requested work
  * downloaded Git files and Helm charts are artifacts served by
    `source-controller`; they are not stored inside the Kubernetes objects

### Manifest, object, `spec` and `status`

* manifest
  * YAML or JSON document that describes an API object to create or update
  * example
    ```yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: web
      namespace: team-a
    spec:
      replicas: 2
      selector:
        matchLabels:
          app: web
      template:
        metadata:
          labels:
            app: web
        spec:
          containers:
            - name: web
              image: httpd:2.4-alpine
    ```
* standard fields
  * `apiVersion`
    * selects an API group and schema version
    * example: `source.toolkit.fluxcd.io/v1` means the stable v1 Source API supplied by Flux
  * `kind`
    * selects a type in that API
    * example: `Deployment`
  * `metadata.name`
    * identifies the object within its resource type and scope
  * `metadata.namespace`
    * is required for namespaced objects unless the client supplies a default
    * is absent for cluster-scoped objects such as `Namespace`, `Node` and
      `CustomResourceDefinition`
    * use `kubectl api-resources --namespaced=true` and
      `kubectl api-resources --namespaced=false` to inspect each category
  * object identity = API group, resource type, namespace when applicable, and name
  * `spec`
    * desired configuration supplied by an API client
        * the client can be a person, `kubectl`, Flux or another controller
    * example: a `Deployment` specification requests two replicas
      ```yaml
      spec:
        replicas: 2
      ```
  * `status`
    * the controller normally updates the object's `/status` API subresource
        * controller report about the observed state and the result of processing `spec`
    * example: `kubectl get deployment web -n team-a -o yaml` returns both `spec` and `status`
* manifest vs object
  * manifest: input sent to the Kubernetes API
  * object: validated API data stored by the Kubernetes control plane
  * flow
      1. `kubectl apply -f deployment.yaml` sends the manifest to the API server
      2. the API server validates and stores `Deployment/web` in namespace
         `team-a`
      3. the built-in Deployment controller creates or updates a `ReplicaSet`
      4. the ReplicaSet controller creates or deletes Pods to reach two replicas
      5. the controllers update the relevant objects' `status` fields
* object vs workload
  * API object: stored record such as a `Deployment`, `Namespace` or `Secret`
  * workload: an application process running in Pods
  * `Deployment/web` in namespace `team-a` is an API object; its Pods run the
    workload
  * not every object creates another object or starts a workload
    * a `Namespace` provides scope for namespaced objects
    * a `Secret` stores sensitive data for authorized clients and Pods

### Status and diagnostics

* purpose
  * show whether a controller has processed the current desired state
  * report success, progress or failure
* `.status.conditions`
  * structured controller reports with fields such as `type`, `status`, `reason`
    and `message`
  * condition types depend on the resource
    * examples: `Ready` on many Flux objects, `Complete` on a `Job`
  * not every resource uses conditions; for example, a `Namespace` uses
    `.status.phase`
* determining whether `status` is current
  * `.metadata.generation` changes when the desired configuration changes
  * `.status.observedGeneration` identifies the generation processed by the
    controller when the resource type provides this field
  * example
    ```yaml
    metadata:
      generation: 4
    status:
      observedGeneration: 3
    ```
    * the controller status still describes generation 3
    * after the controller processes generation 4, it sets
      `status.observedGeneration: 4`
* Kubernetes Events
  * separate, short-lived API objects associated with another object
  * record notable controller activity; they are not fields inside that object
  * `flux events` queries Kubernetes Events for Flux objects from the Kubernetes
    API server
  * example output
    ```text
    $ flux events --for Kustomization/web-prod -n flux-system
    LAST SEEN  TYPE    REASON                   OBJECT                     MESSAGE
    1m         Normal  ReconciliationSucceeded  Kustomization/web-prod     Applied revision: main@sha1:abc123
    ```
* controller logs
  * detailed process output written by controller Pods
  * not stored on the reconciled API object
  * visible with `flux logs` or `kubectl logs`

### Custom APIs and controllers

* CustomResourceDefinition (CRD)
  * cluster-scoped Kubernetes object that registers a custom API group, version,
    resource type, schema and scope
  * after the CRD is installed, the API server can validate and store objects of
    that type
  * provides storage and validation, but implements no controller behavior
* custom resource
  * one API object of a type registered by a CRD
  * uses the Kubernetes API like a built-in object
* custom controller
  * program that watches API objects and implements their requested behavior
  * normally runs in a Pod managed by a `Deployment`
* Flux example
  1. Flux installs the `GitRepository` CRD and the `source-controller`
     Deployment
  2. the CRD registers the `GitRepository` API type
  3. `GitRepository/gitops-flux-workshop` in namespace `flux-system` requests one
     Git source, branch and check interval
  4. `source-controller` watches that object, fetches the repository and updates
     its `status`
* using existing CRDs
  * many open-source projects provide ready-made CRDs and controllers
  * their Helm chart or installation manifests normally install both
    * example: Flux
* creating a custom API
  * first check whether a built-in type or an established project already meets
    the requirement
  * if a new declarative API is required:
    1. define the CRD schema, scope and supported versions
    2. implement a controller that watches the custom resources
    3. deploy the CRD, controller and required RBAC
    4. test validation, reconciliation, upgrades and deletion behavior

## Flux architecture

* Flux controllers run inside Kubernetes
* each controller watches specific Kubernetes API types
* controllers coordinate through specific API objects and their fields
  * example: a Flux `Kustomization.spec.sourceRef` identifies a `GitRepository`
  * example: `GitRepository.status.artifact` identifies files produced by
    `source-controller`
* artifact files are not Kubernetes objects
  * `source-controller` stores the files and serves them inside the cluster
  * Kubernetes objects store the artifact revision, digest and download URL

### Bootstrap boundary

* installing Flux creates its CRDs and starts its controllers
* Flux controllers watch objects stored in the Kubernetes API
  * they do not scan Git repositories for Flux custom-resource manifests
* the first Source and reconciliation objects must be created through one of:
  * `flux bootstrap`
  * a Kubernetes client such as `kubectl`
  * an existing parent Flux reconciliation
* a manifest committed to Git has no effect until an existing reconciliation
  selects the directory containing it
* a Kustomize file used for bootstrap is processed by the invoking client
  * example: `kubectl apply -k <directory>` builds that directory locally and
    sends the resulting objects to the Kubernetes API
  * Flux does not continuously reconcile that bootstrap directory unless a Flux
    `Kustomization` selects it
  * adding another manifest to the directory has no effect until a Kustomize
    resource list selects it and the build output is applied

### Workshop flow: Git to Kubernetes

1. `GitRepository/gitops-flux-workshop` in namespace `flux-system` specifies:
   * repository URL
   * `main` branch
   * one-minute check interval
2. `source-controller` checks the repository
   * `branch: main` is a selection rule whose result can change
   * for each check, the controller resolves that rule to the exact commit
     currently referenced by `main`
3. `source-controller` creates a compressed artifact for that commit
   * the artifact contains the included repository files
   * the controller stores the file and serves it through its in-cluster HTTP
     service
   * it records the commit, digest and URL in
     `GitRepository.status.artifact`
4. `Kustomization/nginx` in namespace `flux-system` reads:
   * `spec.sourceRef.name: gitops-flux-workshop` to select the source object
   * `spec.path: ./apps/nginx` to select a directory inside the
     artifact
5. `kustomize-controller` downloads and verifies the artifact
6. `kustomize-controller` builds the selected directory
   * “build” means read `apps/nginx/kustomization.yaml` and produce the final
     Kubernetes manifests
   * the output contains the Namespace, ConfigMap, Deployment and Service
7. `kustomize-controller` resolves the apply order
   * it applies `Namespace/nginx` before the namespaced objects
   * no separate namespace reconciliation is required
8. `kustomize-controller` compares desired and live objects
   * it uses a server-side apply dry-run during periodic reconciliation
   * if a managed field differs, it applies the desired value through the
     Kubernetes API
   * if nothing differs, repeated reconciliation causes no effective object
     change
   * because `spec.prune: true`, it deletes previously managed objects that are
     absent from the build output
9. built-in Kubernetes controllers process the applied objects
   * example: the Deployment controller creates a ReplicaSet, and the ReplicaSet
     controller creates the requested Pods
   * the Service can exist before the Pods; it gains endpoints when matching Pods
     become ready
10. because `spec.wait: true`, Flux waits for the supported applied objects to
    become ready
11. Flux records the applied revision, inventory and conditions in
    `Kustomization/nginx.status`
12. source changes, API watch events, intervals, retries and manual requests
    trigger later reconciliations

## Flux components

* default installation
  * `source-controller`
  * `kustomize-controller`
  * `helm-controller`
  * `notification-controller`
* optional installation
  * `image-reflector-controller`
  * `image-automation-controller`

### `source-controller`

* purpose
  * watches `GitRepository`, `OCIRepository`, `HelmRepository`, `HelmChart` and
    `Bucket` objects for configuration changes and reconciliation requests
  * checks their external sources at the configured intervals
  * downloads files from Git, Helm repositories, OCI registries or object storage
  * stores the result as a fixed artifact and reports it in the source object's
    `status`
  * does not apply application manifests or manage Helm releases

#### Artifact

* file produced by `source-controller`
  * example: `.tar.gz` snapshot of files from one Git commit
  * not a Kubernetes object and not a container image
* purpose
  * gives downstream controllers an immutable set of files for one resolved
    source revision
  * example
    * `main` is a moving Git branch
    * `main@sha1:abc123` identifies the branch at one exact commit
    * an artifact for that revision contains the selected repository files exactly
      as fetched and filtered for `abc123`
* storage and access
  * the artifact file is stored by `source-controller`
    * source-controller writes to the local path configured by `--storage-path`
    * the standard Flux installation mounts `/data` from an `emptyDir` volume
      * if it is lost after a Pod replacement, source-controller fetches the source
        again and recreates the current artifact
    * this is filesystem storage, not a database
    * a persistent volume can be configured
    * previous artifacts are garbage-collected
      * current defaults keep at most two artifact records after collection
      * previous artifacts become eligible after one minute
      * both values are configurable controller flags; see
        [source-controller options](https://fluxcd.io/flux/components/source/options/)
  * `source-controller` serves the file through its in-cluster HTTP Service
  * the source object's `.status.artifact` does not contain the file
    * example
        ```yaml
        status:
          artifact:
            revision: main@sha1:abc123
            digest: sha256:012345...
            size: 18432
            url: http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/gitops-flux-workshop/abc123.tar.gz
        ```
    * the field contains metadata that allows another controller to find and
      verify the file:
      * `revision`: source revision represented by the artifact
      * `digest`: checksum used to verify the downloaded bytes
      * `size`: artifact size
      * `url`: in-cluster address from which the artifact can be downloaded
  * a consuming controller:
    1. reads the source object's `.status.artifact`
    2. downloads the file from its `url`
    3. verifies it using its `digest`


#### `GitRepository`
* specifies a Git URL, a commit-selection rule and a check interval
* every selection rule resolves to one commit

  | Rule | Result | Typical use |
  |---|---|---|
  | `branch: main` | Current commit referenced by `main` | Deploy every merged change. |
  | `tag: v2.4.1` | Commit referenced by `v2.4.1` | Keep a cluster on one named release until Git changes the tag selection. |
  | `semver: ">=2.0.0 <3.0.0"` | Commit referenced by the highest matching tag | Receive compatible releases automatically. |
  | `commit: abc123...` | Exact commit | Pin an investigation or controlled rollback. |

* a Git server can permit a tag to move; use a commit SHA when the selection must
  remain exact without relying on tag-protection policy

* example: production follows an explicitly selected release tag
  ```yaml
  apiVersion: source.toolkit.fluxcd.io/v1
  kind: GitRepository
  metadata:
    name: production-config
    namespace: flux-system
  spec:
    interval: 1m
    url: https://github.com/company/platform-config.git
    ref:
      tag: v2.4.1
  ```
  * changing `spec.ref.tag` to `v2.4.2` in Git is an explicit production release
    change
* reconciliation
  1. `source-controller` resolves the selection rule to a commit
  2. it checks out that commit in temporary storage
  3. it excludes files matched by `.sourceignore` or `spec.ignore`
  4. it creates the artifact and removes the temporary checkout

#### `HelmRepository`

* points to an HTTP/S Helm chart repository
* `source-controller` downloads `index.yaml`
  * the index maps chart names and versions to chart-package URLs and digests
* rule of thumb
  * use `HelmRepository` when the chart publisher exposes an HTTP/S repository
    with `index.yaml`
  * use `OCIRepository` when the publisher stores the chart in an OCI registry
  * prefer the format already supported by the publisher and the organization's
    authentication, signing and replication tools
  * OCI also supports digest pinning without `index.yaml`

#### `OCIRepository`
* points to an artifact stored in an OCI-compatible registry
* two distinct uses
  * configuration artifact
    * contains Kubernetes manifests or Kustomize files packaged by CI
    * a Flux `Kustomization` can use it instead of a Git artifact
  * Helm chart
    * contains one chart published with the Helm OCI media type
    * `HelmRelease.spec.chartRef` can refer directly to it
* use a configuration artifact when deployment files must move through existing
  registry promotion, signing, retention or replication controls
  * this is an alternative distribution path, not an inherent improvement over
    Git
* tags are mutable references; a digest identifies exact registry content
* example flow for a Helm chart
  1. the chart publisher pushes the chart to
     `oci://ghcr.io/company/charts/webapp`
  2. an `OCIRepository` selects a tag, semantic-version range or digest
  3. `source-controller` downloads the selected registry content and exposes it
     as an artifact
  4. a `HelmRelease` refers to that artifact through `spec.chartRef`

#### `Bucket`

* purpose
  * a Flux `Bucket` object tells `source-controller` to download files from an
    object-storage bucket
  * supported storage includes Amazon S3, Google Cloud Storage, Azure Blob
    Storage and S3-compatible systems such as MinIO
  * the files can contain Kubernetes manifests, Kustomize configuration or a
    Helm chart
* example bucket contents
  ```
  company-production-config
  ├── manifests/
  │   ├── deployment.yaml
  │   ├── service.yaml
  │   └── kustomization.yaml
  └── documentation/
      └── README.md
  ```
* use when configuration is distributed through object storage
  * example: the cluster can access S3 through cloud workload identity but
    cannot access Git
* change detection
  1. an external system uploads Kubernetes configuration files to an
     object-storage bucket
  2. a Flux `Bucket` object tells `source-controller`:
     * which storage service to access
     * which bucket to read
     * how often to check it
  3. `source-controller` lists the included objects
     * an object key is its path, such as `manifests/deployment.yaml`
     * an ETag is an opaque identifier returned for the current representation of
       one object
     * example listing
       ```text
       manifests/deployment.yaml  ETag "a1b2"
       manifests/service.yaml     ETag "c3d4"
       ```
  4. `source-controller` hashes the ordered key-and-ETag list
     * the resulting SHA-256 value represents the observed bucket contents
  5. it compares that value with `Bucket.status.artifact.revision`
     * equal values: keep the existing artifact; no file download is required
     * different values: download the included objects and create a new compressed
       artifact
  6. it records the new revision, digest and artifact URL in `Bucket.status`
  7. a Flux `Kustomization` can refer to the `Bucket` object

### `kustomize-controller`

* watches Flux `Kustomization` objects for creation, specification changes,
  source artifact changes, retry requests and reconciliation intervals
* one Flux `Kustomization` defines one set of source files reconciled together
  * it does not create a Flux `Kustomization` for every applied object
  * the applied Deployments, Services and other objects keep their own Kubernetes
    `status`
* execution model
  * `kustomize-controller` uses the Kustomize Go library; it does not start a
    `kubectl apply -k` process
  * it builds and validates the selected source path in memory
  * it applies the resulting objects directly through the Kubernetes API by
    using server-side apply
  * `kubectl kustomize <path>` is a local way to inspect the build output; it is
    not the command executed by Flux
* workshop example
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: nginx
    namespace: flux-system
  spec:
    interval: 1m
    retryInterval: 20s
    timeout: 2m
    path: ./apps/nginx
    prune: true
    wait: true
    sourceRef:
      kind: GitRepository
      name: gitops-flux-workshop
  ```
* `metadata.name: nginx` is only a descriptive name for this reconciliation
  unit
  * Flux does not derive the source path or target namespace from this name
* Flux `Kustomization` versus Kustomize `kustomization.yaml`
  * Flux `Kustomization`
    * Kubernetes API object watched by `kustomize-controller`
    * selects a source, path, interval and lifecycle options
    * is processed continuously after it is stored in the Kubernetes API
  * Kustomize `kustomization.yaml`
    * file inside the selected directory
    * lists resources, generators, patches and transformations
    * is not stored as a Kubernetes API object
    * is processed when a Flux `Kustomization` reconciles that directory
* reconciliation flow for the example
  1. `kustomize-controller` reads the live `Kustomization/nginx` object
  2. `spec.sourceRef` identifies `GitRepository/gitops-flux-workshop` in the same
     namespace
  3. the controller reads the artifact revision, digest and URL from that source
     object's `status.artifact`
  4. it downloads the compressed artifact, verifies its digest and extracts it
     into a temporary directory
  5. `spec.path` selects `apps/nginx` inside the extracted files
  6. the controller runs the Kustomize build
     * the build reads the committed `kustomization.yaml` resource list
     * the output is a stream of final Kubernetes manifests
     * this does not compile application code or build a container image
  7. it orders the Namespace before the namespaced resources
     * this resolves the structural dependency inside this reconciliation
     * `spec.dependsOn` is used instead when separate Flux `Kustomization`
       objects require readiness ordering
  8. it performs a server-side apply dry-run against the Kubernetes API
     * Kubernetes compares fields managed by Flux with the live objects
     * equal fields require no update
     * different or missing fields produce changes that Flux then applies
  9. if `spec.prune: true`, Flux uses the previous status inventory to delete
     managed objects that are absent from the new build output
  10. if `spec.wait: true`, Flux waits for supported applied objects to become
     ready
  11. it records the attempted revision, applied revision, managed-object
      inventory and readiness conditions in `Kustomization/nginx.status`
  12. it deletes temporary data such as the downloaded archive and extracted
      repository files
* missing `kustomization.yaml`
  * behavior
    * Flux generates one in memory from Kubernetes YAML manifests under
      `spec.path`
    * the generated file is not written to Git
    * Flux has no setting that fails reconciliation only because this file is
      absent
  * limitations
    * resource selection is implicit
      * adding a YAML manifest under the selected tree can add it to the build
    * non-Kubernetes YAML can fail the build unless source ignore rules exclude
      it
    * no Kustomize namespace transformation is declared
      * manifests must declare their namespaces or the Flux `Kustomization` must
        set `spec.targetNamespace`
    * patches, generators and other Kustomize transformations cannot be
      configured for that directory
    * `kubectl kustomize <path>` cannot reproduce the build without a local
      Kustomize file
    * reviewers cannot inspect one explicit list of managed resources
  * recommendation
    * automatic generation is acceptable for a small directory containing only
      Kubernetes manifests
    * otherwise, commit an explicit `kustomization.yaml` so resource selection
      and transformations are reviewable and testable before merge

### `helm-controller`

* terminology
  * Helm chart: versioned package containing templates, default values and
    metadata
  * Helm release: installed instance of a chart; Helm stores its history in the
    cluster, normally in Secrets
  * Flux `HelmRelease`: custom Kubernetes API object that declares the desired
    chart, values and Helm action policies
* responsibility
  * `helm-controller` watches live `HelmRelease` objects
  * a creation, specification change, chart artifact change, referenced-values
    change, interval or retry can trigger reconciliation
  * the controller reads the desired release from the `HelmRelease` and performs
    Helm install, upgrade, test, rollback or uninstall actions
* example
  ```yaml
  apiVersion: helm.toolkit.fluxcd.io/v2
  kind: HelmRelease
  metadata:
    name: web-prod
    namespace: flux-system
  spec:
    interval: 10m
    chart:
      spec:
        chart: webapp
        version: "2.4.1"
        sourceRef:
          kind: HelmRepository
          name: company-charts
    values:
      replicaCount: 3
    driftDetection:
      mode: enabled
  ```
  * `spec.values` overrides values defined by the chart
  * `spec.valuesFrom` can load additional values from Secrets or ConfigMaps
* HTTP/S Helm repository flow
  1. the publisher uploads `webapp-2.4.1.tgz` to a web server or chart service
     and adds its chart name, version, digest and URL to that service's
     `index.yaml`
     * this publication occurs outside Flux
  2. Git contains manifests for `HelmRepository/company-charts` and
     `HelmRelease/web-prod`
  3. a Flux `Kustomization` applies both manifests, creating those two live API
     objects
  4. `source-controller` reconciles the `HelmRepository` after an object change
     or its configured interval
     * it downloads `index.yaml`
     * it stores the index as an artifact
     * it writes the artifact URL to `HelmRepository.status.artifact`
  5. `helm-controller` notices the `HelmRelease`
     * it creates a `HelmChart` object that requests chart `webapp`, version
       `2.4.1`, from `HelmRepository/company-charts`
  6. `source-controller` notices the `HelmChart`
     * it reads the repository index artifact
     * it finds and downloads `webapp-2.4.1.tgz`
     * it stores that package as an artifact
     * it writes the package URL and digest to `HelmChart.status.artifact`
  7. `helm-controller` reads that status, downloads the chart package from the
     internal `source-controller` URL and renders the templates with the values
     from `HelmRelease/web-prod`
  8. it compares the desired chart digest, values and action-relevant
     `HelmRelease.spec` with the last successful Helm release recorded in the
     cluster
     * no recorded release: run Helm install
     * different desired input: run Helm upgrade
     * equal desired input: do not run install or upgrade
  9. with `driftDetection.mode: enabled`, it also checks live Kubernetes objects
     against the manifests recorded by Helm for the current release
     * a server-side dry-run reports which object fields Kubernetes would change
     * no reported change means no drift
     * reported changes are applied to restore the Helm-recorded manifests
  10. it updates the same `HelmRelease/web-prod.status`
* after `HelmChart.status.artifact` is created, the `HelmChart` remains the
  source object for that package
  * it is reconciled when its requested chart or source revision changes
  * `HelmRelease.status.helmChart` identifies it
* OCI alternative
  * `HelmRelease.spec.chartRef` can refer directly to an `OCIRepository`
  * the OCI artifact then replaces the intermediate `HelmChart` in this flow

### `notification-controller`

* handles two independent directions
  * inbound: accept an authenticated webhook and request early reconciliation
  * outbound: forward selected Flux reconciliation results to an external system
* `Receiver`, `Provider` and `Alert` are Flux custom resources, not built-in
  Kubernetes kinds
* `notification-controller` watches these objects for creation and specification
  changes
* it does not fetch Git, render manifests or apply workloads

#### `Receiver`: inbound webhook

* purpose
  * reduce the delay between an external change and the next source check
  * example: a GitHub push requests immediate reconciliation of a
    `GitRepository` instead of waiting for its interval
* polling remains the fallback when delivery fails
* example
  ```yaml
  apiVersion: notification.toolkit.fluxcd.io/v1
  kind: Receiver
  metadata:
    name: platform-github
    namespace: flux-system
  spec:
    type: github
    events:
      - push
    secretRef:
      name: github-webhook-token
    resources:
      - apiVersion: source.toolkit.fluxcd.io/v1
        kind: GitRepository
        name: platform-config
  ```
* after reconciliation, `Receiver.status.webhookPath` contains the generated URL
  path
  * expose `notification-controller` through the cluster's ingress or load
    balancer
  * configure GitHub to send webhook requests to that external host and path
* `secretRef` identifies a Kubernetes Secret in the Receiver namespace
  * the Secret must contain a `token` entry
  * the same random token is configured as the GitHub webhook secret
  * if the Secret manifest uses `stringData`, the token is plain text in that
    manifest
  * base64 encoding in `data` is not encryption
  * do not commit the token unencrypted; use SOPS or an external secret system
  * Kubernetes storage encryption depends on cluster configuration
* HMAC verification
  * HMAC is a keyed message-authentication code
  * it proves that the sender knew the shared token and that the request body was
    not changed
  * it does not encrypt the request body
  1. GitHub calculates an HMAC-SHA256 value from the request body and shared token
  2. GitHub sends the value in `X-Hub-Signature-256`
  3. `notification-controller` calculates the expected value with the Secret token
  4. matching values permit event filtering and reconciliation; different values
     reject the request

#### `Provider` and `Alert`: outbound notification

* purpose
  * notify operators about selected results such as failed production
    reconciliation or a newly applied revision
* `Provider` defines one destination and its authentication
* `Alert` selects Flux objects and minimum event severity, then refers to a
  `Provider`
* Flux controllers attach `info` or `error` severity to notification events
  * this is Flux event metadata
  * it is distinct from the Kubernetes Event `Normal` or `Warning` type
* example: send error events from one production reconciliation to Slack

  ```yaml
  apiVersion: notification.toolkit.fluxcd.io/v1beta3
  kind: Provider
  metadata:
    name: operations-slack
    namespace: flux-system
  spec:
    type: slack
    address: https://slack.com/api/chat.postMessage
    channel: operations
    secretRef:
      name: slack-bot-token
  ---
  apiVersion: notification.toolkit.fluxcd.io/v1beta3
  kind: Alert
  metadata:
    name: production-errors
    namespace: flux-system
  spec:
    providerRef:
      name: operations-slack
    eventSeverity: error
    eventSources:
      - kind: Kustomization
        name: web-prod
  ```
* `slack-bot-token` normally contains a Slack bearer token used to authenticate
  the Slack API request
  * this Slack integration does not use the GitHub webhook HMAC token
  * HMAC is used only by provider types that explicitly support signed webhooks,
    such as `generic-hmac`

### Image controllers

* optional components
  * `image-reflector-controller` discovers image tags and evaluates selection
    policy
  * `image-automation-controller` writes the selected image reference to Git
* use these components when CI publishes container images but another automated
  process must update the deployment repository
  * do not use them when CI or a release process already makes the required Git
    change
* example objects
  ```yaml
  apiVersion: image.toolkit.fluxcd.io/v1
  kind: ImageRepository
  metadata:
    name: payment-api
    namespace: flux-system
  spec:
    image: ghcr.io/company/payment-api
    interval: 5m
  ---
  apiVersion: image.toolkit.fluxcd.io/v1
  kind: ImagePolicy
  metadata:
    name: payment-api-prod
    namespace: flux-system
  spec:
    imageRepositoryRef:
      name: payment-api
    policy:
      semver:
        range: ">=2.0.0 <3.0.0"
  ---
  apiVersion: image.toolkit.fluxcd.io/v1
  kind: ImageUpdateAutomation
  metadata:
    name: payment-api-prod
    namespace: flux-system
  spec:
    interval: 5m
    sourceRef:
      kind: GitRepository
      name: platform-config
    update:
      path: ./apps/payment-api
    git:
      commit:
        author:
          name: flux
          email: flux@example.com
      push:
        branch: main
  ```
* marked Deployment in the selected application directory
  ```yaml
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: payment-api
  spec:
    replicas: 3
    selector:
      matchLabels:
        app: payment-api
    template:
      metadata:
        labels:
          app: payment-api
      spec:
        containers:
          - name: payment-api
            image: ghcr.io/company/payment-api:2.4.0 # {"$imagepolicy": "flux-system:payment-api-prod"}
  ```
* complete flow
  1. application CI builds an image and pushes tags to the GHCR repository
     `ghcr.io/company/payment-api`
  2. at each `ImageRepository.spec.interval`, `image-reflector-controller`
     queries that registry repository and stores the discovered metadata in its
     local cache and Kubernetes status fields
  3. it evaluates `ImagePolicy/payment-api-prod`
     * for tags `2.4.0`, `2.4.1`, `2.5.0-rc.1` and `3.0.0`, the example semantic
       version policy selects stable tag `2.4.1`
     * it writes the selected reference to `ImagePolicy.status.latestRef`
     * it does not change Git or the running Deployment
  4. `image-automation-controller` reconciles
     `ImageUpdateAutomation/payment-api-prod`
     * it checks out the branch configured by `GitRepository/platform-config`
     * it scans `apps/payment-api`
     * the marker names `ImagePolicy/payment-api-prod` in namespace `flux-system`
     * it replaces only the marked image field with
       `ghcr.io/company/payment-api:2.4.1`
     * it commits and pushes that file change to `main`
  5. `source-controller` detects the new Git commit
  6. the Flux `Kustomization` for the application applies the committed
     Deployment image change
* same-repository CI loop
  * this risk exists when application source and deployment YAML share one Git
    repository
  1. an application-source commit triggers the image-build workflow
  2. Flux commits the new image tag to a deployment file in the same repository
  3. an unrestricted workflow treats the Flux commit as another application
     change and builds another image
  * solution: GitHub Actions mitigation
    * restrict the image-build workflow to application and build inputs
    * example from `.github/workflows/build-image.yaml`
      ```yaml
      name: build-image
      on:
        push:
          paths:
            - "src/**"
            - "build.gradle"
            - "Dockerfile"
      ```
    * a Flux commit that changes only `apps/**` does not run this workflow
    * Flux still observes that commit and applies the changed deployment manifest

## Flux versus Argo CD

* both systems pull desired state and compare it with Kubernetes
    * main difference: operational unit presented to users

| Concern | Flux | Argo CD |
|---|---|---|
| Primary unit | A Flux `Kustomization` reconciles one source path. A repository can use several independent Kustomizations. | An `Application` identifies a source, path and destination. Argo CD reports and operates that resource tree as one application. |
| Apply timing | A new observed source revision is reconciled automatically unless the Kustomization is suspended. | Without automated sync, Argo CD detects a difference but waits for a user or API request to synchronize it. |
| Drift correction | Periodic Kustomization reconciliation restores managed fields. | Automatic self-healing must be enabled when live drift should trigger synchronization. |
| Pruning | `Kustomization.spec.prune: true`. | `Application.spec.syncPolicy.automated.prune: true` for automatic pruning; manual synchronization can also prune. |
| Normal topology | Install Flux controllers in each target cluster. | Install Argo CD in a management cluster and register target clusters, or manage the installation cluster itself. |
| User interface | Kubernetes API, Flux CLI, events and logs. | Application API, CLI and web interface with diffs, resource tree, health and sync history. |
| Authorization | Kubernetes RBAC and the ServiceAccount used by a reconciliation. | Argo CD RBAC and `AppProject` restrictions for sources, destinations and resource kinds. |

### Resource organization

* Flux example
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: applications
    namespace: flux-system
  spec:
    interval: 5m
    path: ./applications
    prune: true
    sourceRef:
      kind: GitRepository
      name: platform-config
    dependsOn:
      - name: infrastructure
  ```
  * `Kustomization/infrastructure` and `Kustomization/applications` have separate
    status, retry and source-path configuration
  * `dependsOn` prevents application reconciliation until infrastructure reports
    ready
  * this dependency graph is a direct Flux feature
* Argo CD example
  * infrastructure and workloads can each be managed by an `Application`
  * every resource managed by Argo CD must belong to an Application resource tree
  * ordering inside an Application can use sync phases and waves
  * coordination across separate Applications requires an additional composition
    pattern, such as app-of-apps

### Deployment approval

* Flux normally treats an accepted Git commit as approved desired state
  * source detection triggers reconciliation without a second deployment approval
  * suspending a Kustomization stops all reconciliation; Flux does not create a
    native pending deployment with an approve button
* Argo CD can separate detection from deployment
  * the Application controller calculates the difference after merge
  * with automated sync disabled, the Application remains unsynchronized until a
    user or API client starts synchronization
  * this is useful when deployment authorization is separate from code approval,
    or when production changes must wait for a maintenance window or coordinated
    release
  * the trade-off is that merged Git state does not mean deployed state
* Argo CD can also behave automatically
  ```yaml
  spec:
    syncPolicy:
      automated:
        enabled: true
        prune: true
        selfHeal: true
  ```

### Multiple clusters

* fleet: the set of clusters and applications operated by one platform team
* per-cluster Flux
  * each cluster runs its own controllers and uses in-cluster Kubernetes identity
  * loss of Flux in one cluster stops reconciliation there but does not stop other
    clusters
  * a consolidated fleet list or dashboard requires another aggregation system
* centralized Argo CD
  * the Argo CD control plane runs as Pods in a management cluster
  * it stores each registered target API endpoint and access configuration in
    Kubernetes Secrets
  * its application controller connects from the management cluster to every
    registered target cluster
  * the UI can show application health, revision, synchronization state and
    resources across those clusters
  * if the Argo CD control plane is unavailable, existing workloads continue but
    new comparisons and synchronizations stop
  * compromise of the control plane can affect every target allowed by its stored
    credentials

### Practical selection

* Flux is direct when platform infrastructure and workloads need independent
  in-cluster reconciliation with Kubernetes-native dependencies and RBAC
* Argo CD can manage the same infrastructure, but it must be represented through
  Applications and Argo CD policies
* Argo CD is direct when operators need a centralized application inventory,
  visual diff and manual synchronization after merge
* Flux can support those operating practices only with additional user-interface,
  inventory or approval tooling

## Troubleshooting

### First checks

```bash
flux check
flux get all -A
flux get all -A --status-selector ready=false
```

* `flux check`
  * verifies that required Flux APIs and controller Deployments are available
* `flux get all -A`
  * lists all supported Flux custom resources and their current readiness summary
* `--status-selector ready=false`
  * filters that list to objects whose `Ready` condition is `False`
  * examples include a `GitRepository` that cannot fetch Git, a `Kustomization`
    that cannot apply manifests and a `HelmRelease` whose install failed

### Inspection commands

| Command | Use |
|---|---|
| `kubectl describe` | Show one object's specification, status conditions and recent Kubernetes Events in one report. |
| `flux events` | Filter or watch Kubernetes Events associated with Flux objects. Use it when the event timeline is the focus. |
| `flux logs` | Read detailed controller process logs. Use it when conditions and Events omit the internal error detail. |
| `flux tree kustomization` | Show the resource hierarchy recorded for one Flux Kustomization. |

```bash
kubectl -n <namespace> describe <kind> <name>
flux events --for <kind>/<name> -n <namespace>
flux logs --kind=<kind> --name=<name> \
  --namespace=<namespace> --since=10m
flux tree kustomization <name> -n <namespace>
```

* `flux tree kustomization` prints the object references recorded in the Flux
  Kustomization's `.status.inventory`
  * these are final objects that the Kustomize build produced and Flux applied
    successfully
* log retention depends on the cluster logging configuration
  * `--since=10m` cannot return logs that were already rotated or lost

### Case study: failed `HelmRelease`

1. Find the failed release.

   ```bash
   flux get helmreleases -A --status-selector ready=false --show-source
   ```

2. Read the complete condition and recent Events.

   ```bash
   kubectl -n <release-namespace> describe helmrelease <release-name>
   ```

   Example `Ready` condition:

   ```yaml
   - type: Ready
     status: "False"
     reason: InstallFailed
     message: Helm install failed because Deployment/payment-api was not ready
   ```

   Read a condition as one tuple:

   * `type: Ready` asks whether the desired Helm release is installed and current
   * `status: "False"` answers no
   * `reason: InstallFailed` classifies the failed operation
   * `message` names the immediate cause

   A condition value has meaning only with its type. For example,
   `Drifted=False` means that no drift was detected and is healthy.

3. Identify the failed stage from `reason` and `message`.

   * `InstallFailed`, `UpgradeFailed` or `TestFailed`: that Helm action failed
   * `RollbackFailed` or `UninstallFailed`: automatic failure handling failed
     * remediation is the configured retry, rollback or uninstall response to a
       failed Helm action
   * missing `valuesFrom` reference: inspect the named Secret or ConfigMap
   * unready dependency: inspect the named dependent `HelmRelease`
   * unready `HelmChart`: inspect the chart source path in step 4
   * unready rendered workload: inspect the named Deployment, Job or Pod and the
     configured Helm timeout

4. If the `HelmChart` is not ready, trace chart acquisition.

   ```text
   HelmRepository artifact: index.yaml
     → HelmChart artifact: selected .tgz package
     → HelmRelease: rendered and installed release
   ```

   Check the repository first:

   ```bash
   flux get sources helm -A
   kubectl -n <repository-namespace> describe helmrepository <repository-name>
   ```

   * `Ready=False` means that Flux could not produce the `index.yaml` artifact
   * check the repository URL, authentication, TLS and network error in the
     condition message

   Then check the generated chart source:

   ```bash
   flux get sources chart -A
   kubectl -n <chart-namespace> describe \
     helmchart.source.toolkit.fluxcd.io <chart-name>
   ```

   * `HelmChart.spec` shows the requested chart, version and repository
   * `HelmChart.status.artifact` exists only after `source-controller` finds and
     downloads the selected package
   * `no chart version found` means the requested name or version is absent from
     `index.yaml`
   * `failed to download chart` identifies a package URL, authentication, TLS or
     network failure

5. Read detailed logs only when the status and Events are insufficient.

   ```bash
   flux events --for HelmRelease/<release-name> -n <release-namespace>
   flux logs --kind=HelmRelease --name=<release-name> \
     --namespace=<release-namespace> --since=10m
   ```

6. Correct the cause in Git or in the referenced dependency.

   * normal reconciliation retries according to the `HelmRelease` policy
   * request an immediate retry with `flux reconcile helmrelease <name>`
   * when configured remediation retries are exhausted, use `--reset` only after
     correcting the cause
   * do not delete the `HelmRelease` as a routine troubleshooting step; deletion
     can uninstall the managed release

* [Flux troubleshooting cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/)
