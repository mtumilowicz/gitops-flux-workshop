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

* [`sops-setup/workshop.agekey`](./sops-setup/workshop.agekey)
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
          path: ./apps/application/overlays/production # process files under this path inside that artifact
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
    `apps/application/overlays/production`
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
    * example
        ```
        apiVersion: v1
           entries:
             webapp:
               - version: 2.4.1
                 appVersion: "1.8.0"
                 description: Company web application
                 urls:
                   - https://example.com/charts/webapp-2.4.1.tgz
                 digest: sha256:abc123...
               - version: 2.3.0
                 appVersion: "1.7.0"
                 urls:
                   - https://example.com/charts/webapp-2.3.0.tgz
                 digest: sha256:def456...
        ```
  3. it stores `index.yaml` as the `HelmRepository` artifact
  4. `HelmRelease` requests a chart name and version
    * example
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
        * if the requested version is absent from `index.yaml`
          * `helm-controller` still creates the `HelmChart` object
          * `source-controller` cannot find the requested chart package
          * no `HelmChart.status.artifact` is produced
          * the `HelmChart` reports `Ready=False`
          * the `HelmRelease` cannot proceed with the installation or upgrade
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
          prefix: configuration/production/ # optional key prefix
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

### `helm-controller`

* purpose
  * watches `HelmRelease` objects
  * performs Helm operations inside the cluster without a CI job or a human
    running the Helm CLI
  * keeps the chosen chart, values and failure behavior reconciled

#### Chart, release and Flux objects
* Flux is not powered by Helm
  * Helm support is installed by default, but plain manifests and Kustomize do
    not pass through helm-controller
* helm refresher
    * Helm chart = reusable package containing templates, default values and metadata
      * templates may render a Deployment, Service, RBAC objects and other
        Kubernetes manifests
      * not itself an installed application
    * Helm release = one installed instance of one chart
      * example: the same Redis chart could be installed as separate `dev-redis` and `prod-redis` releases with different values
* Flux objects
  * `HelmRepository`
    * identifies an HTTP/S Helm repository
    * watched by `source-controller`
    * its artifact is the repository's `index.yaml`
  * `HelmRelease`
    * manifest is normally committed to Git
    * `kustomize-controller` applies the manifest and creates the live
      `HelmRelease` object
    * selects the chart name, version and values
    * watched by `helm-controller`
  * `HelmChart`
    * normally created automatically by `helm-controller` from the
      `HelmRelease`
    * requests the selected chart package
    * watched by `source-controller`
    * its artifact is the downloaded chart `.tgz`
  * controller responsibilities
    * `source-controller` obtains the repository index and chart package
    * `helm-controller` renders, installs and continuously reconciles the Helm
      release
* flow
  ```
  HelmRepository
    → identifies an HTTP/S Helm repository

  source-controller
    → downloads its index.yaml
    → stores index.yaml as the HelmRepository artifact

  HelmRelease manifest
    → YAML file committed to Git
    → selects a chart name, chart version and values

  kustomize-controller
    → reads the HelmRelease manifest from the GitRepository artifact
    → applies it to the Kubernetes API

  Kubernetes API
    → stores the live HelmRelease object

  helm-controller
    → detects the HelmRelease object
    → creates a HelmChart object for its chart selection

  source-controller
    → reads the HelmRepository artifact
    → finds the chart's download URL in index.yaml
    → downloads the selected chart package
    → stores the package as the HelmChart artifact

  helm-controller
    → downloads the HelmChart artifact
    → renders the chart using the HelmRelease values
    → installs or upgrades the resulting Kubernetes resources
  ```

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
  type: github # selects GitHub payload parsing and HMAC signature verification
  events:
    - push # ignores other GitHub webhook event types
  secretRef: # Kubernetes Secret in the `Receiver` namespace containing the webhook token
    name: github-webhook-token # same token is configured as the GitHub webhook secret
  resources: # objects to reconcile after an accepted request
    - apiVersion: source.toolkit.fluxcd.io/v1
      kind: GitRepository
      name: platform-config
```
* flow
  1. notification-controller watches the `Receiver` object
    * creates the HTTP path on which this particular Receiver accepts webhooks
    * reports it in `Receiver.status.webhookPath`
  1. An operator exposes the controller's `webhook-receiver` Service through an
     Ingress or another external endpoint.
  1. The complete URL and shared secret are configured in GitHub repository
     webhook settings.
  1. After a push, GitHub sends an HTTP request to that URL.
  1. notification-controller verifies its signature and checks the event type
    * GitHub’s webhook protocol uses a shared secret and HMAC (Hash-based Message Authentication Code)
        * fast and simple
        * each webhook has different secret
    * GitHub
        → calculates an HMAC signature of the request body using the token
        → sends the signature in X-Hub-Signature
    * notification-controller
        → calculates the expected signature using the same token
        → compares the signatures
  1. It requests reconciliation of the listed `GitRepository` through the
     Kubernetes API.
  1. source-controller then contacts Git and resolves the branch tip normally.
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
      name: nginx-prod
```

* flow
  1. `kustomize-controller` encounters an error while reconciling
     `Kustomization/nginx-prod`.
  2. It sends a Flux event containing the involved object, severity, reason,
     message and source revision to notification-controller's event API.
  3. `Alert/production-errors` matches that object and `error` severity.
  4. The Alert references `Provider/operations-slack` in the same namespace.
  5. The Provider supplies the Slack API address, channel and Secret containing
     the bot token.
  6. notification-controller formats and sends the Slack message.

### Image controllers

* optional Flux components
  * useful when CI builds and pushes container images but does not update the
    deployment repository
  * automatically select an allowed image version and commit it to Git
  * unnecessary when CI already updates Git
* example: development environment
  1. Git contains a development Deployment using version `2.4.0`.

     ```yaml
     image: ghcr.io/company/payment-api:2.4.0 # {"$imagepolicy": "flux-system:payment-api-dev"}
     ```

  2. CI builds and pushes new tags to the registry.

     ```text
     2.4.1
     2.5.0-rc.1
     3.0.0
     ```

  3. `image-reflector-controller`
     * scans the registry using an `ImageRepository`
     * applies an `ImagePolicy`, for example:

       ```yaml
       policy:
         semver:
           range: ">=2.0.0 <3.0.0"
       ```

     * selects the highest permitted stable tag: `2.4.1`
     * does not update Git or Kubernetes
  4. `image-automation-controller`
     * finds the marked image field in the development Deployment
     * changes `payment-api:2.4.0` to `payment-api:2.4.1`
     * commits and pushes the change to Git
  5. normal Flux reconciliation deploys the committed image version to the
     development environment
* CI feedback loop
  * problem
    1. an application commit makes CI build and push `payment-api:2.4.2`
    2. image-automation-controller commits `2.4.2` to the staging overlay
    3. if CI builds an image after every commit, that automated commit builds
       another image and the cycle repeats
  * preferred mitigation: run the image-build workflow only when application or
    build files change
    * example
        ```yaml
        on:
          push:
            paths:
              - "src/**"
              - "build.gradle"
        ```
    * a commit changing only `gitops/**` does not match these paths
    * Flux still notices and deploys the Git change
  * alternative: make image-automation-controller add a CI skip instruction to
    its commit message

    ```yaml
    git:
      commit:
        messageTemplate: |
          Update staging image

          [skip ci]
    ```
    * when the automated commit contains `[skip ci]`, GitHub Actions skips workflows
      that would be triggered by that commit through `push` or `pull_request`

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

## Troubleshooting

* start by checking Flux and finding failed objects

  ```bash
  flux check
  flux get all -A --status-selector ready=false
  flux logs -A --level=error --since=10m
  ```

  * `flux check`: reports whether the Flux controllers and required APIs are ready
  * `flux get`: lists not-ready Flux objects and their `MESSAGE`
  * `flux logs`: prints recent error logs from all Flux controllers
    * `--since=10m` does not guarantee ten minutes of logs
        * logs from that period may already have been rotated or lost
* inspect one object
  ```bash
  kubectl -n <namespace> describe <kind> <name>
  flux events --for <kind>/<name> -n <namespace>
  flux logs --kind=<kind> --name=<name> \
    --namespace=<namespace> --since=10m
  ```

  * `kubectl describe`: shows its `spec`, conditions and recent Kubernetes events
  * `flux events`: shows reconciliation events for that object
* inspect the Kubernetes objects managed by one Flux `Kustomization`

  ```bash
  flux tree kustomization <name> -n <namespace>
  ```

  * `flux tree`: shows Kubernetes objects managed by that Flux `Kustomization`

* case study: failing `HelmRelease`
  * example condition from `HelmRelease.status.conditions`

    ```yaml
    - type: Ready
      status: "False"
      reason: InstallFailed
      message: Helm install failed because Deployment/payment-api was not ready
    ```

  * `False` does not always mean failure
  * `False` is meaningful only together with the condition type
  * interpretation
    * `type: Ready`: reports whether the desired release is ready
    * `status: "False"`: the desired release is failing or blocked
    * `reason`: identifies the failure category
    * `message`: identifies the concrete cause
  * common conditions
    * `Ready=True`: release successfully reconciled
    * `Ready=False`: release is failing or blocked
      * `InstallFailed`, `UpgradeFailed` or `TestFailed`: Helm operation failed
      * `RollbackFailed` or `UninstallFailed`: remediation failed
      * message mentions an unready `HelmChart`: chart is unavailable
      * message mentions a dependency: dependent `HelmRelease` is not ready
      * message mentions `valuesFrom`: referenced `ConfigMap` or `Secret` is
        missing or invalid
      * other error in `message`: concrete rendering, validation, timeout or
        Kubernetes resource failure
    * `Reconciling=True`: another attempt is currently running
    * `Drifted=False`: no drift was found; this is healthy
  * inspect the release

    ```bash
    flux get helmreleases -A --show-source
    flux events --for HelmRelease/<release-name> -n <release-namespace>
    flux logs --kind=HelmRelease --name=<release-name> \
      --namespace=<release-namespace> --since=10m
    kubectl -n <release-namespace> describe helmrelease <release-name>
    ```

    * the first command summarizes readiness, chart revision and the latest message
    * events and logs show the failed install, upgrade, test or remediation
  * if the message says that a `HelmChart` is not ready, inspect the source chain
    * Helm cannot install the release until both inputs are ready

      ```text
      HelmRepository index.yaml
        → HelmChart .tgz package
        → HelmRelease installation
      ```

    1. check whether Flux downloaded the repository index

       ```bash
       flux get sources helm -A
       ```

       * shortened failure result

         ```text
         NAME               READY   MESSAGE
         <repository-name>  False   failed to fetch Helm repository: ...
         ```

       * `Ready=False`: Flux cannot read `index.yaml`; check the URL,
         authentication and network
    2. check whether Flux downloaded the selected chart package

       ```bash
       flux get sources chart -A
       ```

       * shortened failure result

         ```text
         NAME          READY   MESSAGE
         <chart-name>  False   no chart version found for <chart>-<version>
         ```

       * `Ready=False`: check the chart name, requested version and download URL
    3. if both are `Ready=True`, the chart source is working
       * inspect the `HelmRelease` events and logs for an install, upgrade, test or
         workload-readiness failure
  * recreate a failed initial installation when its earlier logs are unavailable
    1. preserve the current conditions and events before deleting the object

       ```bash
       kubectl -n <release-namespace> describe helmrelease <release-name>
       flux events --for HelmRelease/<release-name> -n <release-namespace>
       ```

    2. follow new reconciliation logs in terminal one

       ```bash
       flux logs --kind=HelmRelease --name=<release-name> \
         --namespace=<release-namespace> --follow
       ```

    3. delete the failed object in terminal two

       ```bash
       kubectl -n <release-namespace> delete helmrelease <release-name>
       ```

    4. reconcile the Flux `Kustomization` that manages it

       ```bash
       flux reconcile kustomization <kustomization-name> \
         --namespace=<kustomization-namespace> --with-source
       ```

    5. `kustomize-controller` recreates the `HelmRelease` from Git and
       `helm-controller` performs a fresh installation
    * use this only for a failed initial installation
      * deleting a failed upgrade can uninstall a previous working release
* [Flux troubleshooting cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/)
