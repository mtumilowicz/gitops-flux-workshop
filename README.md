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
    * example: `index.html: "environment: dev"`
    * in particular: there is no application project or image build
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
* vs push pipeline

  | Aspect | Push pipeline | Flux |
  |---|---|---|
  | Execution | Runs a deployment command once, then stops. | Runs continuously inside the cluster. |
  | Direction | Pushes changes from CI to Kubernetes. | Pulls desired state from Git. |
  | Credentials | Requires CI to hold Kubernetes credentials. | Uses its in-cluster Kubernetes identity. |
  | Drift | Does not detect changes made after deployment. | Regularly detects and corrects drift. |
  | Retries | Requires a pipeline retry or another run. | Continues retrying failed reconciliation. |
  | Audit records | Can retain Git history, approvals, CI logs, deployment records, and Kubernetes audit logs. | Adds reconciliation status, events, and controller logs to the same Git history. |

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

## Flux architecture and controllers
* problem
  * Git contains the desired state
    * example: Kubernetes `Deployment`, `Service` and `ConfigMap` manifests
  * after a commit, those manifests should appear in Kubernetes
  * if someone changes the live objects manually, they should be restored to the
    state declared in Git
* solution
  * use a reconciliation system that:
    * reads the desired state from Git
    * applies it to Kubernetes
    * continuously compares desired and live state
    * corrects detected drift
  * Flux provides this reconciliation system
* requirements
  * process
    1. watch the Git repository for changes
       * in Flux, a `GitRepository` tells `source-controller` which repository and
         revision to watch
    2. download one exact revision
       * `source-controller` resolves the configured revision to an exact commit
         and downloads its files
    3. package that revision as a fixed artifact
       * `source-controller` publishes the artifact
       * other controllers can use the exact same files without reading a moving
         Git branch
    4. define one or more reconciliation configurations
       * each configuration selects a directory from the artifact
       * in Flux, each configuration is a Flux `Kustomization`
    5. build and apply the manifests selected by each configuration
       * `kustomize-controller`:
         * downloads the Git artifact
         * builds the selected directory
         * applies the resulting objects to the Kubernetes API
       * for ordinary Kubernetes objects:
         * built-in Kubernetes controllers create or update the workloads
       * for an application distributed as a Helm chart:
         1. Git must contain configuration that describes:
            * where the chart is published
              * in Flux, this is a `HelmRepository` or `OCIRepository`
            * which chart and version to use and which values to apply
              * in Flux, this is a `HelmRelease`
         2. an apply component must create those configuration objects in
            Kubernetes
            * in Flux, `kustomize-controller` applies them
         3. a component must obtain the selected chart, render its templates with the
            configured values and install the resulting Kubernetes objects
            * in Flux:
              1. `helm-controller` reads the `HelmRelease`
              2. `source-controller` provides the selected chart as an artifact
              3. `helm-controller` renders the chart with the values from the
                 `HelmRelease`
              4. `helm-controller` installs or upgrades the resulting Kubernetes objects
         4. a release component must combine the chart artifact with the release
            values and manage the resulting installation
            * in Flux, `helm-controller`:
              * downloads the chart artifact
              * reads the values from the `HelmRelease`
              * renders the chart with those values
              * installs or upgrades the resulting Kubernetes objects
    6. repeat the process to detect changes and correct drift
       * `source-controller` detects new Git revisions and chart versions
       * `kustomize-controller` applies the new desired state and restores
         manually changed objects
       * `helm-controller` continuously reconciles each Helm release
    * components
      * source component
        * watches Git
        * resolves a branch, tag or version rule to an exact commit
        * downloads the selected repository files
        * packages them as an artifact
        * in Flux, this is `source-controller`
      * artifact
        * fixed snapshot of the selected repository files
        * prevents later stages from reading a moving Git branch at a different commit
        * contains files; it is not a Kubernetes object or container image
      * apply component
        * reads the artifact
        * selects the configured directory
        * builds the manifests
        * applies them to the Kubernetes API
        * periodically repeats this work to correct drift
        * in Flux, this is `kustomize-controller`
      * Helm support
        * many applications are distributed as Helm charts
        * to deploy such an application, Git must contain manifests that specify:
          * where the chart is published
            * in Flux, this is a source object
              * `HelmRepository` for an HTTP/S Helm repository
              * `OCIRepository` for a chart published in an OCI registry
            * `source-controller` downloads the repository metadata or chart artifact
          * which chart and version to use and which values to apply
            * in Flux, this is a `HelmRelease`
        * `kustomize-controller` applies these objects to the Kubernetes API
          * it does not perform Helm release operations
          * it does not resolve the chart, combine it with values, or manage the Helm
            release lifecycle
        * Helm processing therefore requires another component
          * in Flux, this is `helm-controller`
          * `helm-controller` watches `HelmRelease` objects
          * it obtains the selected chart artifact
          * it renders the chart with the configured values
          * it installs, upgrades and continuously reconciles the Helm release
* architecture
  * Flux consists of several controllers running inside Kubernetes
  * each controller handles one part of the process
    * in particular: no controller owns the complete process
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

### `source-controller`

* purpose
  * watches source objects, including `GitRepository`, `OCIRepository`,
    `HelmRepository`, `HelmChart` and `Bucket`
  * reads configuration packages (files) from systems outside Kubernetes
    * example: Git repository
  * creates an artifact: a fixed snapshot of the downloaded files
    * in particular: does not apply application manifests or run Helm releases

#### Artifact

* file produced by a source reconciliation
  * in particular: only source objects publish artifacts
    * Flux `Kustomization` and `HelmRelease` objects consume artifacts
  * examples: `.tar.gz` snapshot of Git files
      * not a Kubernetes object and not a container image
* purpose
  * prevents two controllers from independently reading a moving branch at
    different commits
  * example
    * `main` is a moving Git branch
    * `main@sha1:abc123` identifies the branch at one exact commit
    * an artifact for that revision contains the selected repository files exactly
      as fetched and filtered for `abc123`
* published through the source object's `.status.artifact`
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
  * `.status.artifact` does not contain the file
    * example
        ```yaml
        status:
          artifact:
            revision: main@sha1:abc123
            digest: sha256:012345...
            size: 18432
            url: http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/gitops-flux-workshop/abc123.tar.gz
        ```
    * it contains metadata that allows another controller to find and verify the
      file:
      * `revision`: source revision represented by the artifact
      * `digest`: checksum used to verify the downloaded bytes
      * `size`: artifact size
      * `url`: in-cluster address from which the artifact can be downloaded
  * a consuming controller:
    1. reads the source object's `.status.artifact`
    2. downloads the file from its `url`
    3. verifies it using its `digest`


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
  1. for every new commit, it performs a new temporary Git checkout
  1. it creates the artifact and removes the temporary checkout

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
The flow should follow the complete controller chain from Git to installation.

* flow
  * assumption
    * a `HelmRepository` object is already configured as a Flux source
    * it points to the HTTP/S Helm repository containing the required chart
  1. `kustomize-controller` reads the `HelmRelease` manifest from the Git
     artifact and applies it to the Kubernetes API
  2. `source-controller` reconciles the `HelmRepository`
     * downloads its `index.yaml`
     * publishes `index.yaml` as the `HelmRepository` artifact
  3. `helm-controller` notices the `HelmRelease`
     * reads `HelmRelease.spec.chart`
     * creates a `HelmChart` object containing:
       * the referenced `HelmRepository`
       * the requested chart name
       * the requested chart version
     * release values remain in the `HelmRelease`
  4. `source-controller` reconciles the `HelmChart`
     * reads the referenced `HelmRepository` artifact
     * finds the requested chart and version in `index.yaml`
     * downloads the chart package
     * publishes the package as the `HelmChart` artifact
     * if the requested chart or version is absent:
       * no `HelmChart.status.artifact` is produced
       * the `HelmChart` reports `Ready=False`
       * the `HelmRelease` cannot continue
  5. `helm-controller` continues reconciling the `HelmRelease`
     * downloads the `HelmChart` artifact
     * reads the values from the `HelmRelease`
     * renders the chart templates with those values
     * installs or upgrades the resulting Kubernetes objects
     * updates `HelmRelease.status`
  6. subsequent reconciliation detects:
     * new chart versions
     * changed `HelmRelease` values
     * drift in the installed release

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

I will inspect the repository’s Flux manifests so the example matches the workshop instead of using invented names.

### `kustomize-controller`
* example
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1 # Flux Kustomization API
  kind: Kustomization                       # object watched by kustomize-controller
  metadata:
    name: nginx-dev                         # name of this reconciliation configuration
    namespace: flux-system                  # namespace containing this Flux object
  spec:
    interval: 1m                            # interval between successful reconciliations
    retryInterval: 20s                      # interval between failed reconciliation attempts
    timeout: 2m                             # maximum duration of one reconciliation
    path: ./apps/nginx/overlays/dev         # directory inside the source artifact
    prune: true                             # delete managed objects removed from Git
    wait: true                              # wait for applied objects to become ready
    sourceRef:                              # source object that publishes the artifact
      kind: GitRepository                   # type of the referenced source object
      name: gitops-flux-workshop            # name of the referenced source object
    dependsOn:                              # reconcile only after these Kustomizations are ready
      - name: namespaces-dev
    decryption:                             # decrypt encrypted manifests before building them
      provider: sops                        # use SOPS for decryption
      secretRef:                            # Secret containing the decryption identity
        name: sops-age
  ```
* purpose
    * turns files from one source artifact into final Kubernetes objects
    * applies those objects and keeps them equal to the desired state
    * does not compile source code or build container images
    * watches Flux `Kustomization` objects
      * Flux `Kustomization` versus Kustomize `kustomization.yaml`
        * Flux [`Kustomization`](https://fluxcd.io/flux/components/kustomize/kustomizations/)
          * Kubernetes API object with
            `apiVersion: kustomize.toolkit.fluxcd.io/v1`
          * tells `kustomize-controller`:
            * which source artifact to use
            * which directory within that artifact to reconcile
            * how often to reconcile it
            * whether to decrypt, wait and prune
          * stored in the cluster
          * its manifest is normally also committed to Git
        * Kustomize `kustomization.yaml`
          * file inside the selected source directory
          * tells the Kustomize builder which resource files, directories, generators
            and patches form the output
          * not a Kubernetes API object sent to the cluster
        * connection
          1. Flux `Kustomization.spec.sourceRef` selects a source artifact
          2. Flux `Kustomization.spec.path` selects a directory inside that artifact
          3. `kustomize-controller` opens the selected directory
          4. if the directory contains `kustomization.yaml`, the controller runs its
             Kustomize build
          5. if it does not contain `kustomization.yaml`, the controller automatically
             generates one for the plain Kubernetes manifests under that directory
          6. the controller applies the generated output to the Kubernetes API
        * naming convention
          * `kustomization.yaml`: Kustomize build file
          * `<purpose>-sync.yaml`: manifest containing a Flux `Kustomization` object
          * `<application>-<environment>`: suggested Flux
            `Kustomization.metadata.name`    
* flow
  1. `kustomize-controller` reads `Kustomization/application`
  2. it follows `Kustomization/application.spec.sourceRef` to
     `GitRepository/application-config`
  3. it reads `GitRepository/application-config.status.artifact`
     * `revision`: source revision contained in the artifact
     * `url`: location from which to download it
     * `digest`: checksum used to verify it
  4. it downloads the artifact through the in-cluster `source-controller`
     Service
     * periodic reconciliation also downloads an unchanged artifact
     * this allows `kustomize-controller` to detect and correct live-cluster drift
  5. it verifies the digest and extracts the artifact into temporary working
     storage
  6. it opens the directory selected by
     `Kustomization/application.spec.path`
  7. it creates the final Kubernetes manifests
     * decrypts encrypted files when configured
     * runs the Kustomize build
     * performs configured variable substitutions
  8. it validates and applies the resulting Kubernetes objects
  9. it performs the configured lifecycle operations
     * when `spec.prune: true`, it deletes previously managed objects that are no
       longer present
     * when configured, it waits for the applied objects to become ready
  10. it updates `Kustomization/application.status`
      * this is the same `Kustomization/application` object read in step 1
      * the status records:
        * last attempted source revision
        * last successfully applied source revision
        * managed-object inventory
        * readiness conditions
      * example

        ```yaml
        kind: Kustomization
        metadata:
          name: application
        status:
          lastAttemptedRevision: main@sha1:abc123
          lastAppliedRevision: main@sha1:abc123
          conditions:
            - type: Ready
              status: "True"
              reason: ReconciliationSucceeded
              message: "Applied revision: main@sha1:abc123"
        ```

  11. it removes the temporary working files
  12. later reconciliation requests
    * the configured interval queues periodic reconciliation
    * a source-object watch event can queue Flux `Kustomization` objects referring
      to a new artifact revision
    * manual requests and retries can also queue reconciliation

### `helm-controller`

* purpose
  * performs Helm operations inside the cluster without a CI job or a human
    running the Helm CLI
  * keeps the chosen chart, values and failure behavior reconciled
  * watches `HelmRelease` objects
* Flux can deploy applications without Helm
  * plain Kubernetes manifests and Kustomize overlays are built and applied by
    `kustomize-controller`
  * `helm-controller` processes only `HelmRelease` objects
  * installing `helm-controller` does not cause ordinary manifests to be rendered
    or managed by Helm
* helm refresher
    * Helm chart = reusable package containing templates, default values and metadata
      * templates may render a Deployment, Service, RBAC objects and other
        Kubernetes manifests
      * not itself an installed application
    * Helm release = one installed instance of one chart
      * example: the same Redis chart could be installed as separate `dev-redis` and `prod-redis` releases with different values
* components
  * `HelmRepository`
    * identifies an HTTP/S Helm repository
    * watched by `source-controller`
    * its artifact is the repository's `index.yaml`
        * example: index.yaml
            ```yaml
            apiVersion: v1
            entries:
              webapp:
                - name: webapp
                  version: 2.4.1
                  appVersion: "1.8.0"
                  description: Company web application
                  urls:
                    - https://example.com/charts/webapp-2.4.1.tgz
                  digest: sha256:abc123...
                - name: webapp
                  version: 2.3.0
                  appVersion: "1.7.0"
                  description: Company web application
                  urls:
                    - https://example.com/charts/webapp-2.3.0.tgz
                  digest: sha256:def456...
            ```
  * `HelmRelease`
    * example
      ```yaml
      kind: HelmRelease
      spec:
        chart:
          spec:
            chart: webapp                    # selects the chart name
            version: "2.4.1"                 # selects the chart version
            sourceRef:                       # identifies where the chart is published
              kind: HelmRepository
              name: company-charts
        values:                              # overrides the chart's (template) default values
          replicaCount: 3
      ```
    * manifest is normally committed to Git
    * `kustomize-controller` applies the manifest and creates the live`HelmRelease` object
  * `HelmChart`
    * normally created automatically by `helm-controller` from the `HelmRelease`
      * an `OCIRepository` referenced through `chartRef` is used directly
    * requests the selected chart package
    * watched by `source-controller`
        * its artifact is the downloaded chart `.tgz`
* flow
  1. a `HelmRepository` identifies an HTTP/S Helm repository
  2. `source-controller` reconciles the `HelmRepository`
     * downloads its `index.yaml`
     * publishes `index.yaml` as the `HelmRepository` artifact
  3. Git contains a `HelmRelease` manifest that selects:
     * chart name
     * chart version
     * release values
  4. `kustomize-controller` reads the `HelmRelease` manifest from the
     `GitRepository` artifact
  5. `kustomize-controller` applies the `HelmRelease` to the Kubernetes API
  6. the Kubernetes API stores the live `HelmRelease` object
  7. `helm-controller` detects the `HelmRelease`
     * reads its chart selection
     * creates a `HelmChart` object
     * keeps the release values in the `HelmRelease`
  8. `source-controller` reconciles the `HelmChart`
     * reads the `HelmRepository` artifact
     * finds the selected chart's download URL in `index.yaml`
     * downloads the chart package
     * publishes the package as the `HelmChart` artifact
  9. `helm-controller` continues reconciling the `HelmRelease`
     * downloads the `HelmChart` artifact
     * reads the values from the `HelmRelease`
     * renders the chart with those values
     * installs or upgrades the resulting Kubernetes objects
     * updates `HelmRelease.status`

### `notification-controller`

* purpose
  * handles two independent directions
    * inbound webhook: an external system asks Flux to reconcile sooner
    * outbound alert: Flux reports a selected event to an external system
  * does not fetch Git, render manifests or apply workloads
  * watches `Receiver`, `Provider` and `Alert` objects

#### `Receiver`: inbound webhook

* problem it solves
  * without a webhook, a push is noticed on the next
    `GitRepository.spec.interval`
  * with a three-minute interval, the delay can be almost three minutes
  * a webhook requests reconciliation immediately after the push
* regular polling is still required
  * it is the fallback when GitHub cannot reach the cluster or a webhook is lost
  * a `Receiver` supplements polling; it does not replace it
* example
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
    * after applying it, notification-controller adds:
      ```
      status:
        webhookPath: /hook/abc123...
      ```
* GitHub webhook authentication with HMAC (Hash-based Message Authentication Code)
  * shared secret
    * one random token is configured in GitHub webhook settings
    * the same token is stored in the Kubernetes Secret referenced by
      `Receiver.spec.secretRef`
    * the token is not included in the webhook request
        1. GitHub calculates an HMAC over the exact request body using the shared secret
            * sends header: `X-Hub-Signature-256`: HMAC-SHA256
        1. `notification-controller` calculates the expected HMAC from the received request body using the same shared secret
            * rejects the request when the signatures differ
            * when they match
                1. reads the GitHub event type from the `X-GitHub-Event` header
                   * example: `push`
                2. checks whether it is listed in `Receiver.spec.events`
                3. for an allowed event, requests reconciliation of the objects listed in
                   `Receiver.spec.resources`
  * why a shared secret is used
    * HMAC is fast and simple for a direct relationship between GitHub and one
      webhook receiver
    * each webhook can use a different secret
    * asymmetric signatures would additionally require public-key distribution,
      selection and rotation
    * trade-off: both GitHub and the receiver possess a secret capable of
      producing a valid signature

#### `Provider` and `Alert`: outbound notification
* example

  ```yaml
  apiVersion: notification.toolkit.fluxcd.io/v1beta3 # Flux notification API
  kind: Provider                                    # outbound destination configuration
  metadata:
    name: operations-slack                          # name referenced by Alert.spec.providerRef
    namespace: flux-system                          # namespace containing Provider and its Secret
  spec:
    type: slack                                     # use the Slack notification integration
    address: https://slack.com/api/chat.postMessage # Slack API endpoint
    channel: operations                             # Slack channel receiving the messages
    secretRef:                                      # Secret containing Slack authentication data
      name: slack-bot-token
  ---
  apiVersion: notification.toolkit.fluxcd.io/v1beta3 # Flux notification API
  kind: Alert                                       # rule selecting events to send
  metadata:
    name: production-errors                         # name of this event-selection rule
    namespace: flux-system                          # namespace containing the referenced objects
  spec:
    providerRef:                                    # Provider used to deliver matching events
      name: operations-slack
    eventSeverity: error                            # send only events with error severity
    eventSources:                                   # Flux objects whose events are considered
      - kind: Kustomization                         # watch events from a Flux Kustomization
        name: nginx-prod                            # select Kustomization/nginx-prod
  ```
* [`Provider`](https://fluxcd.io/flux/components/notification/providers/)
  * tells `notification-controller` where and how to send an outbound notification
  * defines:
    * destination type
      * example: Slack
    * destination address
      * example: Slack API endpoint
    * destination within that system
      * example: Slack channel
    * authentication Secret
      * example: Slack bot token
  * does not select which Flux events should be sent
    * event selection is configured by an `Alert`
  * example: a Slack Provider is a Flux `Provider` object with
    `spec.type: slack`
  * it does not install Slack or create a workspace, app or channel
* [`Alert`](https://fluxcd.io/flux/components/notification/alerts/)
  * rule connecting selected Flux events to one Provider

### Image controllers
* example
    ```yaml
    kind: ImageRepository
    metadata:
      name: payment-api                         # referenced by ImagePolicy
    spec:
      image: ghcr.io/company/payment-api        # registry repository to scan
      interval: 1m                              # scan frequency
    ---
    kind: ImagePolicy
    metadata:
      name: payment-api-dev                     # referenced by $imagepolicy marker
    spec:
      imageRepositoryRef:
        name: payment-api                       # ImageRepository containing scanned tags
      policy:
        semver:
          range: ">=2.0.0 <3.0.0"               # allowed tag versions
    ---
    kind: ImageUpdateAutomation
    metadata:
      name: payment-api-dev                     # Git update configuration
    spec:
      interval: 1m                              # update frequency
      sourceRef:
        kind: GitRepository
        name: gitops-flux-workshop               # Git repository to modify
      update:
        path: ./apps/payment-api/overlays/dev    # directory containing marked fields
      git:
        commit:
          author:
            name: flux
            email: flux@example.com
        push:
          branch: main                           # destination branch
    ```
* optional Flux components
  * useful when CI builds and pushes container images but does not update the
    deployment repository
  * automatically select an allowed image version and commit it to Git
  * unnecessary when CI already updates Git
* example: development environment
    1. Git contains a development Deployment using version `2.4.0`.
    
       ```yaml
       image: ghcr.io/company/payment-api:2.4.0 # {"$imagepolicy": "flux-system:payment-api-dev"}
    * marker format: {"$imagepolicy": "<policy-namespace>:<policy-name>"}
        * is a machine-readable marker for image-automation-controller

  2. CI builds and pushes new tags to the registry.

     ```text
     2.4.1
     2.5.0-rc.1
     3.0.0
     ```

  3. `image-reflector-controller`
     * queries the registry and caches its tags locally
     * applies an `ImagePolicy`, for example:

       ```yaml
       policy:
         semver:
           range: ">=2.0.0 <3.0.0"
       ```

     * selects the highest permitted stable tag: `2.4.1`
     * updates the existing ImagePolicy Kubernetes object
        ```
        status:
          latestRef:
            image: ghcr.io/company/payment-api
            tag: 2.4.1
        ```
     * does not update Git or Kubernetes
  4. `image-automation-controller`
     * watches `ImagePolicy` changes and reconciles at the configured interval
     * constructs a marker key from `ImagePolicy.metadata`:
       `flux-system` + `:` + `payment-api-dev`
       → `flux-system:payment-api-dev`
     * scans `ImageUpdateAutomation.spec.update.path` for the matching marker:
  
       ```yaml
       image: ghcr.io/company/payment-api:2.4.0 # {"$imagepolicy": "flux-system:payment-api-dev"}
       ```
  
     * replaces the marked value with `ImagePolicy.status.latestRef`
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
        * => a commit changing only `gitops/**` does not match these paths
            * but Flux still notices and applies the Git change
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
  1. `kustomize-controller` reads
     `Kustomization.spec.decryption.secretRef.name`
  2. it uses that name to load the Secret from the `Kustomization` namespace
  3. for age, it reads Secret entries whose names end with `.agekey`
  4. it decrypts the encrypted values in memory
     * Flux does not read `.sops.yaml`
     * `.sops.yaml` supplies encryption rules and public recipients when a file is
       encrypted locally
     * the encrypted file already contains the recipient metadata required for
       decryption
     * Flux combines that metadata with the private age key from the referenced
       Secret
  5. it builds and applies the resulting Kubernetes object

## Flux versus Argo CD

* shared model
  * both pull desired state and compare it with live Kubernetes resources
  * the important difference is how they organize ownership and operations
  * for the shared GitOps concepts, see
    [Argo CD](https://github.com/mtumilowicz/argoCD-workshop#argocd)
* reconciliation unit
  * Flux composes independent pipelines
    * sources, infrastructure and workloads can have separate reconciliation,
      dependencies and failure states
    * fits platform repositories where cluster services must become ready before
      applications
    * there is no built-in object that presents the whole pipeline as one application
  * Argo CD organizes delivery around an `Application`
    * one object owns the desired resources, health, drift and synchronization history
    * fits teams that deploy, inspect and operate software as application units
    * infrastructure can be managed, but it must also be represented as applications
* change control
  * Flux normally applies a new source revision as soon as its reconciliation
    pipeline observes it
    * approval normally happens before merge, through the Git workflow
    * suspending reconciliation stops the pipeline rather than creating a pending
      synchronization for an operator to approve
  * Argo CD separates comparison from synchronization
    * an application can report `OutOfSync` while waiting for a manual sync
    * automated sync, pruning and live-state self-healing are explicit policy choices
    * fits environments where an operator must inspect a diff after merge and decide
      when to deploy it
* control-plane topology
  * Flux is commonly installed in every target cluster
    * each cluster reconciles independently and does not depend on a central CD service
    * a controller failure affects its cluster, but fleet-wide inventory requires an
      additional system
  * Argo CD commonly registers many target clusters in one control plane
    * operators get one inventory and operational interface for the fleet
    * control-plane unavailability stops fleet reconciliation; compromise can expose
      every cluster reachable with its registered credentials
* tenancy
  * Flux delegates deployment authority through Kubernetes namespaces, RBAC and
    service accounts
    * fits a platform whose team and security boundaries already exist in Kubernetes
    * each reconciliation can be limited to the permissions of its service account
  * Argo CD delegates application authority through its own RBAC and `AppProject`
    policies
    * projects restrict allowed sources, destination clusters, namespaces and resource
      kinds
    * fits a central platform where users operate applications without direct access
      to target clusters
* fleet rollout
  * Flux commonly stores desired state per cluster and promotes changes by changing
    the relevant cluster paths or revisions
    * fits clusters that may intentionally differ or be operated independently
  * Argo CD can generate applications from cluster and repository data with
    `ApplicationSet`
    * fits centrally applying a standard application catalogue across many registered
      clusters
* operator workflow
  * Flux exposes reconciliation through Kubernetes resources, events and logs
    * fits operators who already diagnose systems through Kubernetes APIs and
      observability tools
  * Argo CD adds an application-focused API and web interface
    * fits operators who need one place for application health, resource topology,
      diffs, history and synchronization actions
* choose Flux when the critical requirement is
  * independent reconciliation inside each cluster
  * one delivery model for both platform infrastructure and workloads
  * authorization that follows existing Kubernetes tenancy boundaries
* choose Argo CD when the critical requirement is
  * centralized inventory and operation of many applications or clusters
  * manual synchronization or visual diff review after a Git change
  * application operations for users who should not access target clusters directly

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
    flux get helmreleases -A --status-selector ready=false --show-source
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
       flux get sources helm -A --status-selector ready=false
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
       flux get sources chart -A --status-selector ready=false
       ```

       * shortened failure result

         ```text
         NAME          READY   MESSAGE
         <chart-name>  False   no chart version found for <chart>-<version>
         ```

       * inspect the failed `HelmChart`

         ```bash
         kubectl -n <chart-namespace> describe \
           helmchart.source.toolkit.fluxcd.io <chart-name>
         ```

         * `Spec.Chart`: requested chart name
         * `Spec.Version`: requested version
         * `Spec.Source Ref`: referenced `HelmRepository`
         * `Conditions` and `Events`: concrete failure
       * common messages
         * `no chart version found`: chart name or version is absent from
           `index.yaml`
         * `failed to download chart`: package URL, authentication or network failed
         * `HelmRepository ... is not ready`: fix the repository first
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
