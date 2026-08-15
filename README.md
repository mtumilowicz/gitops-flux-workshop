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
  * Kubernetes API server, resources, desired state, built-in controllers,
    namespaces, Deployments, Services, ConfigMaps, Secrets and RBAC from:
    https://github.com/mtumilowicz/kubernetes-workshop
  * Kustomize bases, overlays and patches from: https://github.com/mtumilowicz/kustomize-workshop
  * SOPS recipients, identities and encrypted YAML from: https://github.com/mtumilowicz/sops-age-key-workshop
* scope: covers only the Flux-specific use of Kustomize and SOPS

### Warning

* [`local-setup/workshop.agekey`](./local-setup/workshop.agekey)
  * disposable private identity committed for reproducibility
  * provides no confidentiality
* production private identities
  * must be delivered outside Git

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
* Flux
  * keeps reviewed desired state in Git
  * runs controllers inside the target environment
  * pulls desired state and continuously reconciles it with the live system
* vs push-pipeline
  * execution
    * a one-shot push pipeline runs a deployment command and then stops
    * Flux runs continuously inside the cluster
  * direction
    * a push pipeline sends changes from CI to Kubernetes
    * Flux pulls desired state from Git
  * credentials
    * a push pipeline requires CI to hold Kubernetes credentials
    * Flux uses its in-cluster Kubernetes identity
  * drift
    * a one-shot pipeline does not detect changes made after deployment
    * Flux regularly compares live resources with Git and corrects drift
  * retries
    * a failed push requires a pipeline retry or another run
    * Flux keeps retrying failed reconciliation
  * audit records
    * a push pipeline can retain Git commits, pull-request approvals, CI logs,
      deployment records and Kubernetes audit logs
    * Flux can retain the same Git history plus reconciliation status, events
      and controller logs
  * important distinction
    * auditability records what happened
    * reconciliation continuously restores the declared desired state
* Flux reconciliation
  * convergence
    * creates or updates resources until the cluster matches Git
  * drift correction
    * changes done manually are restored
  * deletion
    * resources removed from desired state can be pruned
  * auditability
    * Git records who proposed and approved a change
  * recovery
    * a previous desired state can be restored with another Git commit
* state
  * Git records desired state
  * Kubernetes status records current health and observed state

## Kubernetes API model used by Flux

* core idea
  * Flux does not introduce a separate configuration database or deployment API
  * it extends the Kubernetes API with new resource types and runs controllers
    that act on objects of those types

### Manifest, object, `spec` and `status`

* manifest
  * YAML or JSON document sent to the Kubernetes API
  * example
    ```yaml
    apiVersion: v1
    kind: Namespace
    metadata:
      name: nginx-dev
    ```
* standard fields
  * `apiVersion`
    * selects an API group and schema version
    * example: `source.toolkit.fluxcd.io/v1` means the stable v1 Source API supplied by Flux
  * `kind`
    * selects a type in that API
    * example: `Deployment`
  * `metadata.name` and `metadata.namespace`
    * identify this particular object
    * the full identity is API group, kind, namespace and name
        * metadata.name may be repeated when the kind or namespace differs
  * `spec`
    * specification supplied by the user
    * example: a `Service` specification selects Pods and exposes port 80
      ```yaml
      spec:
        selector:
          app: nginx
        ports:
          - port: 80
      ```
  * `status`
    * report written by the controller after it tries to satisfy `spec`
    * is stored on the Kubernetes object
        * example: kubectl get namespace nginx-dev -o yaml
            ```
            apiVersion: v1
            kind: Namespace
            metadata:
              name: nginx-dev
            status: # <--- status
              phase: Active
            ```
* manifest vs object
  * object: data stored in the Kubernetes API
  * flow
      1. `kubectl apply -f namespace.yaml` sends the YAML manifest to the API server
      2. the API server validates it and stores `Namespace/nginx-dev`
      3. the built-in namespace controller reconciles the stored object
      4. Kubernetes reports the result in its `status`, for example
         `status.phase: Active`
* object vs workload
  * workload = application running in Kubernetes Pods
  * example:
    * `Deployment/nginx` is an object
    * the nginx Pods created from it are the workload
  * objects such as `Namespace` and `Secret` do not create workloads
* status channels
  * `.status.conditions`
    * many native Kubernetes objects use .status.conditions, but not all
        * example
            * Namespace uses .status.phase
            * Job: Complete, Failed
                ```yaml
                status:
                  conditions:
                    - type: Complete
                      status: "True"
                ```
            * Pod: Ready, PodScheduled, Initialized
                * `Ready=True` means the latest observed configuration succeeded;
                  `Ready=False` includes a reason and message
  * generation tracking
    * `.metadata.generation`
      * updated by the API server when the desired configuration changes
    * `.status.observedGeneration`
      * updated later by the responsible controller
      * identifies the generation described by the current `status`
    * comparison
      * equal values: the controller processed the current configuration
      * different values: the reported status may describe an older configuration
  * Kubernetes events
    * timestamped diagnostic records associated with an object
    * visible in `kubectl describe` or with `flux events`
        * example: flux events -n specificNamespace
  * controller logs
    * detailed records written by the controller process
    * visible with `flux logs` or `kubectl logs`

### CRD, custom resource and controller

* built-in versus custom types
  * Kubernetes already understands built-in types such as `Namespace`, `Service`
    and `Secret`
  * a CRD adds a type that Kubernetes does not provide
* example: complete relationship
```text
ExternalSecret CRD
  → registers the ExternalSecret API type

ExternalSecret/database-password
  → requests one external value and one target Kubernetes Secret

external-secrets controller
  → watches the ExternalSecret
  → fetches the external value
  → creates or updates Secret/database-password
  → updates ExternalSecret.status
```
* CustomResourceDefinition (CRD)
  * cluster-scoped Kubernetes object that registers a custom API type and its
    validation schema
  * defines whether objects of that type are namespaced or cluster-scoped
  * stores no application data and implements no behavior
  * without the CRD:
    * the API server does not recognize the custom API type
    * attempts to create objects of that type are rejected
    * a controller may start, but attempts to list or watch that type fail
* custom resource
  * one object of a type registered by a CRD
  * stored and accessed through the Kubernetes API like a native object
  * its `spec` describes the requested behavior
  * its `status` can report the result
* custom controller
  * program that implements the behavior requested by custom resources
  * normally runs in a Pod managed by a native Kubernetes `Deployment`
  * for each watched custom resource, it:
    1. reads the requested state from `spec`
    2. inspects the current state
    3. performs the required operations
    4. reports the result in `status`, events and logs
  * without the controller:
    * the API server can store and validate the custom resources
    * nothing performs the behavior requested by their `spec`
    * their controller-managed `status` is not updated

### Watch and reconciliation

* watch
  * long-running subscription from a controller process to the Kubernetes API
    server
  * the controller's ServiceAccount requires RBAC permissions to `list` and
    `watch` the selected resource type
* reconciliation
  1. an object's identity is added to the controller's work queue
     * initial discovery when the controller starts
     * creation, modification or deletion reported through an API watch
     * change to a watched related object
     * timer, retry or explicit request
  2. a worker removes the identity from the queue
  3. it reads the latest object
     * if the object no longer exists, processing normally ends
  4. it reads the desired configuration from `spec`
  5. it inspects the relevant current state
  6. it performs any required operations
  7. it may update `status` and emit events or logs
  8. the reconciliation returns one outcome:
     * finished without requeueing
        * future watch event or other external trigger can still enqueue the object
     * request another reconciliation after a delay
     * report a failure that may be retried

I will inspect the surrounding README structure and the reference README. Then I will provide replacement text in chat only.

Use the existing nested-bullet style:

## Flux architecture and controllers
* architecture
  * Flux consists of several controllers running inside Kubernetes
  * each controller handles one part of the process
  * controllers communicate through objects stored in the Kubernetes API
* notifications
  * Flux controllers emit Kubernetes events
  * `notification-controller` can forward selected events to systems such as
    Slack or Microsoft Teams
* default installation
  * `source-controller`
  * `kustomize-controller`
  * `helm-controller`
  * `notification-controller`
* optional installation
  * `image-reflector-controller`
  * `image-automation-controller`
* no controller owns the complete process
  * each controller performs, retries and reports its own part

### `source-controller`

* purpose
  * watches source objects, including `GitRepository`, `OCIRepository`,
    `HelmRepository`, `HelmChart` and `Bucket`
  * reads configuration packages (files) from systems outside Kubernetes
    * example: Git repository
  * creates an artifact: a fixed snapshot of the downloaded files
      * in particular: does not apply application manifests or run Helm releases
      * example: the Git branch `main` can move whenever a new commit is pushed
        1. `source-controller` finds the exact commit currently referenced by `main`
        2. it downloads the files from that commit
          * for every new commit, source-controller performs a new Git checkout
              * Temporary Git checkout is removed after the artifact is created
        3. it creates a compressed archive called an artifact
          * older artifacts are removed by garbage collection
              * default maximum: 2 artifacts per source
        4. it stores the artifact in its `/data` directory
           * `/data` is backed by an `emptyDir` volume by default
              * replacing the Pod removes all artifacts when the default emptyDir storage is used
           * this is filesystem storage, not a database
           * a persistent volume can be configured
        5. it updates the `GitRepository/application-xyz` object
      
           ```yaml
           status:
             artifact:
               revision: main@sha1:363a6a8fe6a7f13e05d34c163b0ef02a777da20a
               digest: sha256:e750c7a46724acaef8f8aa926259af30bbd9face2ae065ae8896ba5ee5ab832b
               size: 91318
               url: http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/application-xyz/363a6a8f.tar.gz
           ```
      
           * `revision`: exact Git commit contained in the artifact
           * `digest`: checksum of the artifact
           * `size`: artifact size in bytes
           * `url`: internal address from which another controller can download it
        6. another Flux object refers to the `GitRepository`
      
           ```yaml
           apiVersion: kustomize.toolkit.fluxcd.io/v1
           kind: Kustomization
           metadata:
             name: application
             namespace: flux-system
           spec:
             interval: 5m
             path: ./apps/application-xyz
             sourceRef:
               kind: GitRepository
               name: application-xyz
           ```
      
        7. `kustomize-controller`:
           1. reads `GitRepository/applicationXyz` from the Kubernetes API
           2. reads its `status.artifact.url`
           3. downloads the archive over HTTP through the internal `source-controller` Kubernetes Service
           4. uses the files under `./apps/applicationXyz`

#### Artifact

* definition
  * file produced by a source reconciliation
  * examples: `.tar.gz` snapshot of Git files
  * not a Kubernetes object and not a container image
* purpose:prevents two controllers from independently reading a moving branch at different commits
    * example
      * `main` is a moving Git branch
      * `main@sha1:abc123` identifies the branch at one exact commit
      * an artifact for that revision contains the selected repository files exactly
        as fetched and filtered for `abc123`

#### `GitRepository`
* GitRepository = what Git repository and revision to download
    * example
        ```
        apiVersion: source.toolkit.fluxcd.io/v1
        kind: GitRepository
        metadata:
          name: application-config
          namespace: flux-system
        spec:
          interval: 1m # how often to check it
          url: https://github.com/company/application-config.git # which Git repository to read
          ref: # rule used to select a commit
            branch: main # means:aAt every check, use the commit currently pointed by main
        ```
* Flux Kustomization = what directory from that artifact to build and apply
    * example
        ```
        apiVersion: kustomize.toolkit.fluxcd.io/v1
        kind: Kustomization
        metadata:
          name: production
          namespace: flux-system
        spec:
          interval: 5m
          sourceRef: # use the artifact produced by this source
            kind: GitRepository 
            name: application-config
          path: ./clusters/production # process files under this path inside that artifact
          prune: true
        ```
* rules used to select a commit
  * branch: select the commit currently at the end of the branch
  * semantic-version range: select the highest matching tag, then its commit
    * useful for automatically receiving new releases from one allowed major version
    * example: range >=2.0.0 <3.0.0 
  * tag: select the commit identified by that tag
    * useful when Flux should deploy a named release instead of following every commit on a branch
  * commit SHA: select that exact commit
    * useful for an exact deployment, rollback or investigation
  * all choices finally resolve to a commit
    * branch main              → commit abc123
    * tag v2.4.1               → commit abc123
    * range >=2.0.0 <3.0.0     → tag v2.4.1 → commit abc123
    * commit abc123            → commit abc123
* flow
  1. `GitRepository` specifies a Git URL, commit-selection rule and check interval
  1. `source-controller` resolves the rule to an exact commit
  1. it downloads that commit and creates a Git artifact
  1. `kustomize-controller` downloads the artifact
  1. it reads the manifests from the selected directory
  1. it sends the resulting objects to the Kubernetes API
  1. processing now depends on each object's kind
     * native Kubernetes object, such as `Deployment`
       1. the API server stores the `Deployment`
       2. the built-in Deployment controller creates a `ReplicaSet`
       3. the `ReplicaSet` creates Pods
     * Flux `HelmRelease` object
       1. the API server stores the `HelmRelease`
       2. `helm-controller` notices it
       3. it obtains the requested chart
          * creates a `HelmChart` when the chart comes from a `GitRepository`,
            `HelmRepository` or `Bucket`
          * directly uses an `OCIRepository` referenced through `chartRef`
       4. it renders the chart with the configured values
       5. it installs or upgrades the resulting Kubernetes objects

#### `OCIRepository`
* OCI = open standards for packaging and transferring images and artifacts
    * example: Docker Hub supports OCI
* the artifact can contain:
  * Helm chart
  * plain Kubernetes or Kustomize configuration
* example:
  1. CI packages the Kubernetes YAML and Kustomize files from
    `clusters/production`
  1. CI pushes the package to
    `oci://ghcr.io/company/cluster-config:v2.4.1`
  1. Flux uses an `OCIRepository` to download that package
* less common than storing deployment configuration directly in Git
* useful when CI packages configuration as a versioned release
    * allows every cluster to download the same package by tag or digest
* flow
  1. `OCIRepository` specifies:
     * OCI registry URL
     * chart tag, version range or digest
  2. `source-controller` downloads the selected Helm chart
  3. it stores the chart as an artifact
  4. `HelmRelease.spec.chartRef` refers to the `OCIRepository`
  5. `helm-controller` downloads the chart artifact
  6. it combines the chart templates with the `HelmRelease` values
    * example
        * chart is a template
            ```
            spec:
              replicas: {{ .Values.replicaCount }}
            ```
        * chart defaults are in values.yaml
            ```
            replicaCount: 1
            ```
        * HelmRelease can override it
            ```
            spec:
              values:
                replicaCount: 3
            ```
  7. it installs or upgrades the resulting Kubernetes resources
  
#### `HelmRepository`
* vs `OCIRepository`
  * both can provide Helm charts to Flux
  * `HelmRepository`
    * points to an HTTP/S chart repository
    * reads `index.yaml` to find chart names, versions and download URLs
  * `OCIRepository`
    * points to a container registry
    * selects a chart by tag, version range or digest
    * does not use `index.yaml`
  * use `HelmRepository` when charts are published on a traditional Helm
    repository
  * use `OCIRepository` when charts are published in an OCI registry
* flow
  1. a `HelmRepository` specifies an HTTP/S chart repository

     ```yaml
     kind: HelmRepository
     spec:
       interval: 1h
       url: https://example.com/charts
     ```

  2. `source-controller` downloads the repository's `index.yaml`
  3. it stores `index.yaml` as the `HelmRepository` artifact
  4. a `HelmRelease` selects a chart from that repository

     ```yaml
     kind: HelmRelease
     spec:
       chart:
         spec:
           chart: webapp
           version: "2.4.1"
           sourceRef:
             kind: HelmRepository
             name: company-charts
     ```
  5. `helm-controller` creates a `HelmChart` object from
     `HelmRelease.spec.chart.spec`
  6. `source-controller` processes the `HelmChart`
     * reads the referenced `HelmRepository` index
     * finds chart `webapp`, version `2.4.1`
     * downloads the chart package
     * stores it as the `HelmChart` artifact
  7. `helm-controller` uses the chart artifact
     * renders the chart templates
     * applies values from the `HelmRelease`
     * installs or upgrades the resulting Kubernetes resources
  8. `helm-controller` reports the result in `HelmRelease.status`

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
* use cases
    * vendor publishes deployment files only through a bucket
    * cluster can access S3 through cloud workload identity but cannot access Git
* flow
  1. an external system uploads Kubernetes configuration files to an
     object-storage bucket
  2. a Flux `Bucket` object tells `source-controller`:
     * which storage service to access
     * which bucket to read
     * how often to check it
  3. `source-controller` checks whether the included files changed
     * asks the storage service for the included object keys and ETags
        ```
        spec:
          provider: aws
          endpoint: s3.amazonaws.com
          bucketName: company-config
          prefix: clusters/production/ # optional key prefix
        ```
     * calculates one revision checksum from that list
     * compares it with the revision stored in `Bucket.status.artifact.revision`
  4. when they changed, it:
     * downloads all included files
     * creates a compressed artifact
     * records the artifact URL in `Bucket.status`
  5. a Flux `Kustomization` can refer to the `Bucket` object
  6. `kustomize-controller` downloads the artifact and applies its Kubernetes
     manifests
     
#### Publishing and consuming artifacts
* publish means
  1. write the artifact file under the controller's local storage path
  2. expose it through the `source-controller` Kubernetes Service
  3. update the source object's `.status.artifact`
    * purpose of `.status.artifact`
      * tells other controllers:
        * which source revision the artifact contains
        * where to download it
        * which checksum to use for verification
    * example
        ```yaml
        status:
          artifact:
            revision: main@sha1:abc123
            digest: sha256:012345...
            size: 18432
            url: http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/gitops-flux-workshop/abc123.tar.gz
        ```
* fields
  * `revision` = external version selected by the controller
    * example
        * for git - exact Git commit downloaded by Flux
        * for bucket - calculated by Flux from the included object names and their change identifiers
  * `digest` = checksum of the produced bytes; consumers can verify the download
  * `size`= artifact size in bytes
  * `url` = in-cluster HTTP address for the exact artifact
* storage
  * source-controller writes to the local path configured by `--storage-path`
  * the standard Flux installation mounts `/data` from an `emptyDir` volume
    * if it is lost after a Pod replacement, source-controller fetches the source
      again and recreates the current artifact
  * previous artifacts are garbage-collected
    * current defaults keep at most two artifact records after collection
    * previous artifacts become eligible after one minute
    * both values are configurable controller flags; see
      [source-controller options](https://fluxcd.io/flux/components/source/options/)
* consumption by `kustomize-controller`
  1. a Flux `Kustomization.spec.sourceRef` identifies the source object
  2. `kustomize-controller` reads that object's `.status.artifact`
  3. it downloads the exact URL through cluster DNS
     * it downloads an unchanged artifact during periodic reconciliation
       * needed to detect and correct live-cluster drift
  4. it verifies the digest and extracts the file into temporary working storage
  5. it opens the directory specified by `Kustomization.spec.path`
  6. it creates the final Kubernetes manifests
     * decrypts encrypted files when configured
     * runs the Kustomize build
     * performs configured variable substitutions
  7. it validates the resulting Kubernetes objects
  8. it applies them to the Kubernetes API
  9. when `spec.prune: true`, it deletes previously managed objects that are no
     longer present
  10. when configured, it waits for the applied objects to become ready
  11. it updates the Flux `Kustomization.status`
      * last applied source revision
      * managed-object inventory
      * readiness conditions
      * example
        ```
        kind: Kustomization
        status:
          lastAttemptedRevision: main@sha1:abc123
          lastAppliedRevision: main@sha1:abc123
          conditions:
            - type: Ready
              status: "True"
              reason: ReconciliationSucceeded
              message: "Applied revision: main@sha1:abc123"
        ```
  12. it removes the temporary working files
* later reconciliation requests
  * the configured interval queues periodic reconciliation
  * a source-object watch event can queue Flux `Kustomization` objects referring
    to a new artifact revision
  * manual requests and retries can also queue reconciliation

### `kustomize-controller`

* purpose
  * watches Flux `Kustomization` objects
  * turns files from one source artifact into final Kubernetes objects
  * applies those objects and keeps them equal to the desired state
  * does not compile source code or build container images

#### Two meanings of `Kustomization`

* Flux [`Kustomization`](https://fluxcd.io/flux/components/kustomize/kustomizations/)
  * Kubernetes API object with
    `apiVersion: kustomize.toolkit.fluxcd.io/v1`
  * tells the controller which source and directory to reconcile, how often to
    reconcile it, and whether to decrypt, wait and prune
  * stored in the cluster; normally its manifest is also committed to Git
* Kustomize `kustomization.yaml`
  * file inside the selected source directory
  * tells the Kustomize builder which resource files, directories, generators
    and patches form the output
  * is not a Kubernetes API object sent to the cluster
* naming convention
  * `kustomization.yaml`: Kustomize build file
  * `<purpose>-sync.yaml`: manifest containing a Flux `Kustomization` object
  * `<application>-<environment>`: suggested Flux `Kustomization.metadata.name`

#### Workshop input

* [`clusters/dev/nginx.yaml`](./clusters/dev/nginx.yaml) is the Flux object

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: dev-nginx
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: gitops-flux-workshop
  path: ./apps/nginx/overlays/dev
  decryption:
    provider: sops
    secretRef:
      name: sops-age
  prune: true
  wait: true
```

* `sourceRef`
  * points to `GitRepository/gitops-flux-workshop` in `flux-system`
  * the referenced object's `status.artifact` supplies the exact repository
    snapshot and Git revision
* `path`
  * directory inside that extracted snapshot
  * not a local path in the controller container and not a GitHub URL
* `decryption`
  * tells the controller to use the private age identity from
    `Secret/sops-age` when it encounters SOPS-encrypted input
* `prune` and `wait`
  * delete obsolete owned objects and wait for applied objects to become ready

* the selected directory contains these build instructions

```yaml
# apps/nginx/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: nginx-dev
resources:
  - ../../base
  - configmap.yaml
  - secret.enc.yaml
patches:
  - path: deployment-patch.yaml
```

* because this directory contains `kustomization.yaml`, only files reached from
  its resources, generators, components or patches take part in this build
* if `spec.path` contains no Kustomize file, kustomize-controller can generate
  build instructions automatically from the YAML files it finds there
* `../../base/kustomization.yaml` loads the reusable base
  * [`deployment.yaml`](./apps/nginx/base/deployment.yaml) defines
    `Deployment/nginx`
  * [`service.yaml`](./apps/nginx/base/service.yaml) defines `Service/nginx`
* reusable base means source YAML reused by both environment builds
  * dev and prod do not share one live `Deployment`
  * each overlay renders and applies a separate `Deployment` in its namespace
* [`deployment-patch.yaml`](./apps/nginx/overlays/dev/deployment-patch.yaml)
  matches the object by API version, kind and name
  * the dev patch sets `Deployment/nginx` to one replica
  * the prod patch sets its separately rendered Deployment to two replicas

#### One reconciliation

1. `kustomize-controller` resolves `sourceRef` through the Kubernetes API.
2. It waits until the `GitRepository` reports a ready artifact.
3. It downloads and verifies the artifact, then opens
   `apps/nginx/overlays/dev` inside it.
4. It follows `resources` into the base and loads the Deployment, Service,
   ConfigMap and encrypted Secret manifests.
5. It decrypts the SOPS document in memory before building.
6. Kustomize applies the dev patch and the `nginx-dev` namespace transformation.
7. The build output is four ordinary Kubernetes objects:
   `Deployment/nginx`, `Service/nginx`, `ConfigMap/nginx-index` and
   `Secret/nginx-workshop-secret`, all in `nginx-dev`.
8. The controller checks the objects with the Kubernetes API and applies them
   with server-side apply.
9. With `wait: true`, it checks their health until they are ready or the timeout
   expires.
10. It records the applied object identities in `.status.inventory`.
11. With `prune: true`, it deletes an object from that inventory when a later
    successful build no longer contains it.

#### Meaning of the controller operations

* decrypt
  * convert a referenced SOPS-encrypted manifest to plaintext in memory
  * the encrypted file remains encrypted in Git
* build
  * render a deterministic set of final Kubernetes manifests from the declared
    Kustomize inputs
* validate and apply
  * submit the final objects to the Kubernetes API using server-side dry-run and
    server-side apply
  * schema, admission-policy or authorization errors fail the reconciliation
* check
  * inspect readiness for supported objects when health waiting is enabled
  * for this workshop, that includes waiting for the nginx Deployment rollout
* prune
  * delete successfully applied objects that this Flux `Kustomization` owns and
    that disappeared from its latest successful output
  * it does not delete arbitrary objects in the namespace

### `helm-controller`

* purpose
  * watches `HelmRelease` objects
  * performs Helm operations inside the cluster without a CI job or a human
    running the Helm CLI
  * keeps the chosen chart, values and failure behavior reconciled

#### Chart, release and Flux objects

* Helm chart
  * reusable package containing templates, default values and metadata
  * templates may render a Deployment, Service, RBAC objects and other
    Kubernetes manifests
  * not itself an installed application
* Helm release
  * one installed instance of one chart with a release name, namespace, merged
    values and revision history
  * a Helm concept, not one Kubernetes workload object
    * rendered Deployments, Services and other objects are the installed content
    * Helm normally stores release history as Helm-owned Secrets in Kubernetes
  * the same Redis chart could be installed as separate `dev-redis` and
    `prod-redis` releases with different values
* `HelmRepository`
  * source-controller object describing where chart packages can be found
* `HelmChart`
  * source-controller object requesting one chart package from a source
  * its artifact is the selected `.tgz` package used by helm-controller
* `HelmRelease`
  * desired-state object watched by helm-controller
  * declares which chart to install, its version and values, and policies for
    upgrades, tests and failures

* these are related objects, not different representations of one object

```text
HelmRepository: where charts are available
        ↓ referenced by
HelmChart:      fetch this chart package and version
        ↓ artifact consumed by
HelmRelease:    install one release from that package with these values
        ↓ Helm operation creates or updates
Kubernetes objects: Deployment, Service, ConfigMap, ...
```

* a `HelmRelease` manifest by itself does not install anything
  * Kubernetes can store it because the CRD exists
  * helm-controller supplies the behavior that turns it into Helm actions
* a Flux `Kustomization` commonly applies the `HelmRepository` and `HelmRelease`
  objects from Git
  * kustomize-controller stops after creating or updating those API objects
  * with health waiting enabled, it can wait for the `HelmRelease` to report
    ready, but it does not perform the Helm install
  * source-controller and helm-controller then perform their own work
* Flux is not powered by Helm
  * Helm support is installed by default, but plain manifests and Kustomize do
    not pass through helm-controller

#### ingress-nginx example

* Git contains two desired-state manifests
* `Namespace/ingress-nginx` must exist before the namespaced `HelmRelease` can be
  created
* repository location and polling configuration

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: ingress-nginx
  namespace: flux-system
spec:
  interval: 10m
  url: https://kubernetes.github.io/ingress-nginx
```

* requested installed release

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
spec:
  interval: 10m
  chart:
    spec:
      chart: ingress-nginx
      version: "4.13.0"
      sourceRef:
        kind: HelmRepository
        name: ingress-nginx
        namespace: flux-system
  values:
    controller:
      replicaCount: 2
```

* exact connection
  1. kustomize-controller applies both custom resources from the Git artifact.
  2. source-controller fetches the `HelmRepository` `index.yaml` and publishes
     that exact index as an artifact.
  3. helm-controller notices `HelmRelease/ingress-nginx`.
  4. From `spec.chart.spec`, it creates an associated `HelmChart` object in the
     source namespace. That object requests chart `ingress-nginx` version
     `4.13.0` from `HelmRepository/ingress-nginx`.
     `HelmRelease.status.helmChart` reports the associated object's reference.
  5. source-controller notices the `HelmChart`, finds that chart and version in
     the repository index, downloads the `.tgz`, and publishes it as the
     `HelmChart` artifact.
  6. helm-controller waits for that artifact, downloads it and merges the chart's
     default values with `controller.replicaCount: 2` from the `HelmRelease`.
  7. It renders the chart templates and performs a Helm install. The rendered
     Kubernetes objects are submitted to the API server in the release
     namespace. Because `spec.targetNamespace` is omitted, this is the
     `HelmRelease` namespace, `ingress-nginx`.
  8. It records the result and current chart revision in the `HelmRelease`
     `status`.
* later behavior
  * a changed chart version or values normally causes a Helm upgrade
  * configured Helm tests can run after install or upgrade
  * failure policies can retry, roll back or uninstall a failed revision
  * deleting the `HelmRelease` normally causes helm-controller to uninstall the
    release
* the controller uses the Helm libraries and Helm release model
  * it does not convert the chart into a Flux `Kustomization`
  * the generated `HelmChart` requests a package whose artifact is fixed for one
    revision; the `HelmRelease` remains the desired installed instance
* workshop scope
  * this workshop does not create a `HelmRepository`, `HelmChart` or `HelmRelease`

### `notification-controller`

* purpose
  * watches `Receiver`, `Provider` and `Alert` objects
  * handles two independent directions
    * inbound webhook: an external system asks Flux to reconcile sooner
    * outbound alert: Flux reports a selected event to an external system
  * does not fetch Git, render manifests or apply workloads

#### `Receiver`: inbound webhook

* problem it solves
  * without a webhook, a push is noticed on the next
    `GitRepository.spec.interval`
  * with a three-minute interval, the delay can be almost three minutes
  * a webhook requests reconciliation immediately after the push
* regular polling is still required
  * it is the fallback when GitHub cannot reach the cluster or a webhook is lost
  * a `Receiver` supplements polling; it does not replace it
* example object

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

* field meanings
  * `type: github`
    * selects GitHub payload parsing and HMAC signature verification
  * `events: [push]`
    * ignores other GitHub webhook event types
  * `secretRef`
    * points to a Kubernetes Secret in the `Receiver` namespace containing the
      webhook token
    * the same token is configured as the GitHub webhook secret
  * `resources`
    * exact Flux objects to reconcile after an accepted request
    * here it is `GitRepository/platform-config`, not every source in the cluster
* setup and flow
  1. notification-controller watches the `Receiver` object.
  2. It calculates a unique path and reports it in
     `Receiver.status.webhookPath`.
  3. An operator exposes the controller's `webhook-receiver` Service through an
     Ingress or another external endpoint.
  4. The complete URL and shared secret are configured in GitHub repository
     webhook settings.
  5. After a push, GitHub sends an HTTP request to that URL.
  6. notification-controller verifies its signature and checks the event type.
  7. It requests reconciliation of the listed `GitRepository` through the
     Kubernetes API.
  8. source-controller then contacts Git and resolves the branch tip normally.
* the webhook does not send all commits or apply their files
  * it is a prompt meaning “check this source now”
  * source-controller still produces one snapshot for the newest selected
    revision

#### `Provider` and `Alert`: outbound notification

* [`Provider`](https://fluxcd.io/flux/components/notification/providers/)
  * destination and authentication configuration
  * a Slack Provider is a Flux `Provider` object with `spec.type: slack`
  * it does not install Slack or create a workspace, app or channel
* [`Alert`](https://fluxcd.io/flux/components/notification/alerts/)
  * rule connecting selected Flux events to one Provider
  * selects involved objects and severity; optional rules can filter messages
* Slack error example

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
      name: prod-nginx
```

* connection
  1. `kustomize-controller` encounters an error while reconciling
     `Kustomization/prod-nginx`.
  2. It sends a Flux event containing the involved object, severity, reason,
     message and source revision to notification-controller's event API.
  3. `Alert/production-errors` matches that object and `error` severity.
  4. The Alert references `Provider/operations-slack` in the same namespace.
  5. The Provider supplies the Slack API address, channel and Secret containing
     the bot token.
  6. notification-controller formats and sends the Slack message.
* other Provider types can send generic webhooks, Microsoft Teams messages,
  Git commit statuses and events to other supported systems

* workshop scope
  * no `Receiver`, `Provider` or `Alert` resources are included
  * Kubernetes events and controller logs remain available locally

### `image-reflector-controller`

* purpose
  * watches `ImageRepository` and `ImagePolicy` objects
  * discovers tags available in a container registry
  * calculates which tag satisfies a declared rule
  * does not change Git or a running Kubernetes workload

#### Configuration

* the configuration is stored in Kubernetes objects
  * their manifests are normally committed to Git and applied by a Flux
    `Kustomization`
  * they are not configured in the container registry or in a controller file
* example

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageRepository
metadata:
  name: payment-api
  namespace: flux-system
spec:
  image: ghcr.io/company/payment-api
  interval: 1m
  secretRef:
    name: registry-credentials
---
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImagePolicy
metadata:
  name: payment-api
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: payment-api
  policy:
    semver:
      range: ">=2.0.0 <3.0.0"
```

* `ImageRepository`
  * `spec.image` is a registry repository without a tag
  * `spec.interval` controls registry scans
  * `spec.secretRef` is optional for a public registry; for a private registry it
    points to credentials in a Kubernetes Secret in the same namespace
* `ImagePolicy`
  * `imageRepositoryRef` points to the scanned tag set
  * `policy` defines how to choose one tag
  * supported ordering policies are semantic-version, alphabetical and numerical

#### Scan and selection

1. image-reflector-controller calls the registry API for
   `ghcr.io/company/payment-api` every minute.
2. It lists tag metadata; it does not pull and run every container image.
3. It stores the tag set in a rebuildable internal controller database and
   reports scan time and tag count in `ImageRepository.status`.
4. When that set changes, it reevaluates `ImagePolicy/payment-api`.
5. Suppose the registry contains `2.4.0`, `2.4.1`, `2.5.0-rc.1` and `3.0.0`.
6. The semantic-version range excludes the prerelease and major version 3, so
   the selected tag is `2.4.1`.
7. The result is reported on the policy object.

```yaml
status:
  latestRef:
    image: ghcr.io/company/payment-api
    tag: 2.4.1
```

* “selects” therefore means “calculates and writes `ImagePolicy.status`”
  * nothing is deployed from this result by image-reflector-controller
  * an operator can inspect it
  * image-automation-controller can use it to update marked Git fields

### `image-automation-controller`

* purpose
  * watches `ImageUpdateAutomation` objects
  * writes results from `ImagePolicy.status.latestRef` into marked YAML fields
  * commits and pushes those edits to Git

#### Why update Git

* example problem
  1. Git declares `payment-api:2.4.0`.
  2. CI builds and pushes permitted image `payment-api:2.4.1`.
  3. image-reflector-controller selects `2.4.1`.
  4. Git still declares `2.4.0`, so normal GitOps reconciliation still deploys
     `2.4.0`.
* changing only the live Deployment would be incorrect
  * Git would no longer describe the live state
  * kustomize-controller would detect drift and restore `2.4.0`
  * there would be no Git commit recording the deployment change
* image automation closes the loop by making `2.4.1` the new desired state in
  Git

#### Update configuration

```yaml
apiVersion: image.toolkit.fluxcd.io/v1
kind: ImageUpdateAutomation
metadata:
  name: payment-api
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: platform-config
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        name: flux-image-automation
        email: flux@example.com
    push:
      branch: main
  update:
    path: ./apps/payment
    strategy: Setters
```

* target selection
  * `sourceRef`
    * identifies the `GitRepository` whose remote URL and authentication are used
    * authentication must permit Git push, not only read
  * `git.checkout`
    * branch used as the input working tree
  * `git.push`
    * branch receiving the new commit
  * `update.path`
    * limits the YAML scan to one directory in that checkout
  * image policy marker
    * inline YAML comment identifying the policy for one scalar field
    * the automation lists policies in its namespace; it has no separate
      `policyRef` field

* marked Deployment field

```yaml
image: ghcr.io/company/payment-api:2.4.0 # {"$imagepolicy": "flux-system:payment-api"}
```

* marker meaning
  * `flux-system` is the `ImagePolicy` namespace
  * `payment-api` is its name
  * the basic marker updates the complete image value on that YAML line
  * an unmarked image field is left unchanged

#### One update

1. `ImagePolicy/payment-api` reports tag `2.4.1` in `status.latestRef`.
2. On its interval, image-automation-controller reads
   `ImageUpdateAutomation/payment-api`.
3. It uses `GitRepository/platform-config` for the Git URL and write
   credentials, then checks out `main`.
4. It scans YAML under `apps/payment` and finds the marker for
   `flux-system:payment-api`.
5. It changes only the marked value to
   `ghcr.io/company/payment-api:2.4.1`.
6. It creates a Git commit with the configured author and pushes it to `main`.
7. It reports the pushed commit in `ImageUpdateAutomation.status.lastPushCommit`.
8. source-controller notices that new Git commit and publishes a new artifact.
9. Normal Kustomize or Helm reconciliation deploys the committed value.

* approval workflow
  * direct push to `main` deploys without a pull-request approval
  * `git.push.branch` can instead target an automation branch
  * separate CI automation can open a pull request from that branch; Flux image
    automation does not create the pull request itself
* workshop scope
  * the image controllers are optional and are not configured in this workshop

### Controller path used by this workshop

* active Flux objects
  * one `GitRepository`
  * four Flux `Kustomization` objects: namespace and nginx reconciliation for
    dev and prod
* reconciliation path

```text
Git branch main
  → source-controller resolves its current commit
  → GitRepository.status.artifact identifies that fixed snapshot
  → kustomize-controller downloads the snapshot
  → each Flux Kustomization selects its spec.path
  → Kustomize follows the resources and patches declared at that path
  → encrypted Secrets are decrypted in memory
  → final objects are applied through the Kubernetes API
  → readiness, status and inventory are updated
```

* controller use
  * source-controller and kustomize-controller perform the workshop deployment
  * helm-controller is installed but receives no `HelmRelease`
  * notification-controller is installed but receives no `Receiver`, `Provider`
    or `Alert` configuration
  * image controllers are not installed by `flux install` unless explicitly
    requested
* source trigger
  * the workshop has no webhook Receiver
  * source-controller discovers a new commit during its one-minute interval or
    after a manual `flux reconcile source git` request
  * a new artifact revision causes the referencing Flux `Kustomization` objects
    to reconcile without waiting for their next drift-check interval

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

* definition
  * [`clusters/source.yaml`](./clusters/source.yaml) defines one source for both
    environments
* configuration

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

* fields
  * `apiVersion`
    * selects the stable Source API
  * `kind`
    * selects the `GitRepository` resource
  * `metadata.name`
    * identifies the source
  * `metadata.namespace`
    * determines its namespace and reference scope
  * `spec.interval`
    * schedules Git checks
  * `spec.url`
    * identifies the remote repository
  * `spec.ref.branch`
    * resolves the tip of `main`
* successful `source-controller` reconciliation
  1. resolves the configured reference to a commit
  2. applies default exclusions and `.sourceignore`
  3. archives the remaining content
  4. publishes the artifact inside the cluster
  5. reports revision, digest, size and URL in `.status.artifact`
* artifact identity
  * the revision identifies the Git input
  * the digest identifies the produced artifact content
  * they are different because files may be excluded

## Flux `Kustomization`

* definition
  * [`clusters/dev/nginx.yaml`](./clusters/dev/nginx.yaml) defines the dev
    reconciliation pipeline
* configuration

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

* fields
  * `apiVersion`
    * selects the stable Flux Kustomize API
  * `kind`
    * selects the Flux `Kustomization` resource
  * `metadata.name`
    * identifies this pipeline
  * `metadata.namespace`
    * places it in `flux-system`
  * `spec.interval`
    * schedules successful reconciliation approximately every minute
  * `spec.retryInterval`
    * retries failures after 20 seconds
  * `spec.timeout`
    * limits build, apply and health-check operations to two minutes
  * `spec.path`
    * selects a directory in the source artifact
  * `spec.prune`
    * enables deletion of objects removed from desired state
  * `spec.wait`
    * checks all reconciled resources for readiness
  * `spec.sourceRef.kind`
    * selects the source type
  * `spec.sourceRef.name`
    * selects `GitRepository/gitops-flux-workshop`
  * `spec.dependsOn[].name`
    * waits for `dev-namespaces` to be ready
  * `spec.decryption.provider`
    * enables SOPS
  * `spec.decryption.secretRef.name`
    * selects `Secret/sops-age`
* source namespace
  * `sourceRef.namespace` is omitted
  * Flux therefore looks for the source in the Flux `Kustomization` namespace,
    `flux-system`

### Artifact-relative path

* rule
  * `spec.path` starts at the artifact root
  * it does not start beside `clusters/dev/nginx.yaml`
* artifact path

```text
GitRepository artifact
└── apps/nginx/overlays/dev
    └── kustomization.yaml
```

* result
  * `./apps/nginx/overlays/dev` is valid
  * `./overlays/dev` is not

### Flux `Kustomization` versus Kustomize

* Flux `Kustomization`
  * Kubernetes custom resource
  * read by `kustomize-controller`
  * selects a source artifact and path
  * reconciles continuously
  * supports readiness, retry, dependency, decryption and pruning
* Kustomize `kustomization.yaml`
  * Kustomize build instructions
  * read by Kustomize
  * selects resources, generators and patches
  * renders once per invocation
  * does not manage runtime state
* relationship

```text
clusters/dev/nginx.yaml
  → sourceRef: GitRepository/gitops-flux-workshop
  → path: apps/nginx/overlays/dev
  → apps/nginx/overlays/dev/kustomization.yaml
  → nginx-dev resources
```

### How the dev overlay is built

* resource discovery
  * this overlay has a `kustomization.yaml`, so Kustomize does not automatically
    load every YAML file in the directory
  * a `resources` list explicitly defines the files and Kustomize directories
    that participate in the build
* dev overlay resources

```yaml
resources:
  - ../../base
  - configmap.yaml
  - secret.enc.yaml
```

* build process
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
* resource identity
  * filenames do not identify Kubernetes resources
  * `deployment.yaml` and `deployment-patch.yaml` could be renamed if their
    `kustomization.yaml` references were updated
  * patch matching comes from `apiVersion`, `kind` and `metadata.name` inside
    the YAML

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
* pipeline ownership
  * the namespace and workload pipelines are separate
  * pruning `dev-nginx` does not remove `nginx-dev`, which belongs to
    `dev-namespaces`

## SOPS decryption

* input
  * Flux receives the encrypted files through the source artifact
* reconciliation-time process
  1. `kustomize-controller` reads `decryption.secretRef.name`
  2. it loads `identity.agekey` from `Secret/sops-age` in `flux-system`
  3. it decrypts the encrypted values in memory
  4. it builds and applies a normal Kubernetes Secret
* `.sops.yaml`
  * supplies the public recipient when the local SOPS CLI creates or updates a
    file
  * Flux does not use it to decrypt an existing file
  * decryption uses the encrypted file metadata and the private identity in the
    Kubernetes Secret
* protection boundary
  * SOPS protects secret values stored in Git
  * it does not authorize a deployment
  * it does not protect plaintext already stored in Kubernetes
  * it does not prove that a Git change is safe

## Flux versus Argo CD

* shared concepts
  * both implement pull-based continuous delivery for Kubernetes
  * for Argo CD concepts already covered by its workshop, see
    [Argo CD](https://github.com/mtumilowicz/argoCD-workshop#argocd)
* operating models
  * differ between Flux and Argo CD
* primary abstraction
  * Flux: sources plus specialized reconciliation resources
  * Argo CD: `Application`, `ApplicationSet` and `AppProject`
* architecture
  * Flux: composable Kubernetes controllers
  * Argo CD: application controller, repository server, API server and integrated UI
* built-in interface
  * Flux: Kubernetes API and Flux CLI
  * Argo CD: Kubernetes API, Argo CD API, CLI and web UI
* installation lifecycle
  * Flux: bootstrap can make Flux manage itself from Git
  * Argo CD: installation followed by declarative application configuration
* multi-cluster style
  * Flux: commonly installed per cluster; remote reconciliation is also supported
  * Argo CD: commonly centralizes registered clusters in one control plane
* Kustomize
  * Flux: reconciled by `kustomize-controller`
  * Argo CD: rendered by the repository server for an `Application`
* Helm
  * Flux: `HelmRelease` manages Helm release operations
  * Argo CD: Helm renders manifests; Argo CD manages application lifecycle
* SOPS
  * Flux: native decryption in `kustomize-controller`
  * Argo CD: normally requires a plugin or separate secret solution
* image updates
  * Flux: official optional Flux image controllers write to Git
  * Argo CD: normally uses the separate Argo CD Image Updater or another tool
* notifications
  * Flux: `Receiver`, `Alert` and `Provider` APIs
  * Argo CD: integrated Argo CD Notifications
* tenancy
  * Flux: Kubernetes RBAC, namespaces and service-account impersonation
  * Argo CD: Argo CD RBAC and `AppProject` source, destination and resource
    restrictions
* visual operations
  * Flux: no built-in Flux web UI
  * Argo CD: built-in application topology, health, diff and synchronization UI
* choose Flux when
  * Kubernetes-native APIs and controller composition are preferred
  * GitOps bootstrap and self-management are important
  * native SOPS decryption is required
  * image selection and Git write-back should use official Flux controllers
  * teams prefer Kubernetes RBAC and CLI-driven operation
  * explicit dependencies between reconciliation pipelines are useful
* choose Argo CD when
  * a central application inventory and web interface are primary requirements
  * operators need visual health, diffs, history and synchronization controls
  * `ApplicationSet` should generate applications across clusters or repositories
  * `AppProject` is a good fit for application-level tenancy and policy
  * a central control plane managing registered clusters matches the operating model
* decision
  * neither is universally better
  * consider the required interface, cluster topology, tenancy boundary, secret
    workflow, Helm semantics, Git write-back and the team's operational experience

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

* prerequisites
  * Docker Desktop Kubernetes
  * `kubectl`
  * Flux CLI
  * SOPS
  * this repository committed to a reachable `main` branch

### 1. Verify prerequisites

```bash
kubectl config current-context
flux check --pre
```

* expected
  * context `docker-desktop`
  * `prerequisites checks passed`

### 2. Install Flux

```bash
flux install
kubectl -n flux-system wait deployment --all \
  --for=condition=Available \
  --timeout=2m
kubectl -n flux-system get deployments
```

* expected
  * the four default controllers are available in `flux-system`

### 3. Provide the age identity

```bash
kubectl apply -k local-setup
kubectl -n flux-system get secret sops-age
```

* expected
  * `Secret/sops-age` is `Opaque`
  * contains one data entry

### 4. Connect the source

* when using a fork
  * change `spec.url` in `clusters/source.yaml`
  * commit and push before continuing

```bash
kubectl apply -k clusters
flux reconcile source git gitops-flux-workshop
```

* expected
  * status contains `stored artifact for revision 'main@sha1:<commit>'`
* inspect the artifact

```bash
kubectl -n flux-system get gitrepository gitops-flux-workshop \
  -o jsonpath='{.status.artifact.revision}{"\n"}{.status.artifact.digest}{"\n"}{.status.artifact.url}{"\n"}'
```

* expected
  * a `main@sha1:` revision
  * a `sha256:` digest
  * an internal artifact URL

### 5. Reconcile dev and prod

```bash
flux reconcile kustomization dev-namespaces
flux reconcile kustomization dev-nginx
flux reconcile kustomization prod-namespaces
flux reconcile kustomization prod-nginx
flux get kustomizations
```

* expected
  * all four resources report `Ready=True` at the selected revision
* verify the replica counts

```bash
kubectl -n nginx-dev get deployment nginx
kubectl -n nginx-prod get deployment nginx
```

* expected
  * dev reports `1/1`
  * prod reports `2/2`

### 6. Read both pages

```bash
kubectl -n nginx-dev port-forward service/nginx 8080:80
```

* from another terminal

```bash
curl --silent http://localhost:8080
```

* expected
  * `environment: dev`
* prod
  * stop the dev port-forward
  * repeat with `-n nginx-prod`
  * expected: `environment: prod`

### 7. Verify Flux decryption

```bash
kubectl -n nginx-dev get secret nginx-workshop-secret \
  -o jsonpath='{.data.environment}' | base64 --decode
echo
```

* expected
  * `dev`
  * Git contains ciphertext
  * Kubernetes contains the Secret produced after in-memory decryption

### 8. Observe a Git change

* prerequisite
  * a writable remote configured in `clusters/source.yaml`

```bash
perl -pi -e 's/environment: dev/environment: dev-updated/' \
  apps/nginx/overlays/dev/configmap.yaml
git add apps/nginx/overlays/dev/configmap.yaml
git commit -m 'Update dev page'
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
```

* with the dev port-forward running
  * allow for projected ConfigMap propagation

```bash
until curl --silent http://localhost:8080 | grep -q 'environment: dev-updated'; do
  sleep 2
done
```

* restore the original Git state

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

* expected
  * the desired count changes to four
  * it then returns to the Git value one

### 10. Observe failure, retry and dependency blocking

```bash
kubectl -n flux-system patch kustomization dev-namespaces \
  --type=merge \
  --patch='{"spec":{"path":"./does-not-exist"}}'
flux reconcile kustomization dev-namespaces
```

* expected failure
  * the command fails
* observe the 20-second retries

```bash
kubectl -n flux-system get kustomization dev-namespaces --watch
```

```bash
flux events --for Kustomization/dev-namespaces
flux reconcile kustomization dev-nginx
```

* expected
  * `dev-namespaces` is `Ready=False`
  * `dev-nginx` reports that its dependency is not ready
* restore the committed object

```bash
kubectl apply -f clusters/dev/namespaces.yaml
flux reconcile kustomization dev-namespaces
flux reconcile kustomization dev-nginx
```

* expected
  * both dev pipelines return to `Ready=True`

### 11. Observe pruning from Git

* change
  * remove `secret.enc.yaml` from the `resources` list in
    `apps/nginx/overlays/dev/kustomization.yaml`
  * commit and push

```bash
git add apps/nginx/overlays/dev/kustomization.yaml
git commit -m 'Remove dev workshop secret'
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get secret nginx-workshop-secret
```

* expected
  * Kubernetes reports `NotFound`
  * pruning removed the owned Secret
* restore it through Git

```bash
git revert --no-edit HEAD
git push
flux reconcile source git gitops-flux-workshop
flux reconcile kustomization dev-nginx
kubectl -n nginx-dev get secret nginx-workshop-secret
```

* expected
  * the Secret exists again

## Troubleshooting

* follow the failed stage from source to workload

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

* source not ready
  * check URL, branch, credentials, network and source conditions
* old revision
  * check pushed branch, artifact revision and source reconciliation
* build failure
  * check artifact-relative `spec.path` and selected Kustomize file
* dependency failure
  * check dependency name and `Ready` condition
* readiness timeout
  * check Pods, events, image pull and probes
* SOPS failure
  * check `sops-age`, `identity.agekey`, recipient and MAC
* persistent drift
  * check suspension, source revision and field ownership
* unexpected deletion
  * check pruning configuration and object inventory
* error location
  * status conditions and object-scoped events normally contain the first
    actionable error

## Cleanup

```bash
kubectl delete -k clusters
kubectl wait namespace/nginx-dev --for=delete --timeout=2m
kubectl wait namespace/nginx-prod --for=delete --timeout=2m
kubectl delete -k local-setup
```

* expected
  * the workshop source, reconciliation objects, namespaces and age identity
    are removed
  * Flux remains installed
* dedicated disposable cluster only

```bash
flux uninstall --namespace=flux-system
```

* restriction
  * do not uninstall Flux from a cluster where it manages other workloads

# troubleshoot
* helmrelease one condition false, why?