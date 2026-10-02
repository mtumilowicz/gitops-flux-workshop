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
  | Operational records | CI records each pipeline run and deployment command. Kubernetes can record the resulting API requests in its audit log. | Flux records reconciliation status and Events in Kubernetes. Controller logs are stored by the cluster logging system. Git history is separate and is available in both models. |

* Kubernetes reconciliation refresher
    * example
        * `Deployment` object declares a Pod template and a replica count
        * the Deployment controller creates or updates a `ReplicaSet`
        * the ReplicaSet controller creates or deletes Pods until the requested replica
          count is reached
        * if a Pod is deleted, the ReplicaSet controller creates a replacement
        * each controller reads desired state from Kubernetes API objects, changes the
          current state and reports the result through object status and Events
* Git as the source of truth
  * Git contains the reviewed desired Kubernetes configuration
    * example: the live `Deployment` is not the source; it is one object produced from that
      configuration
  * Flux implements the control loop between Git and the Kubernetes API
    * convergence: create or update objects until their Flux-managed fields match
      the configuration selected from Git
    * drift correction: restore Flux-managed fields changed directly in the
      cluster
    * pruning: with `spec.prune: true`, delete previously managed objects removed
      from the selected Git configuration
    * dependency ordering: `spec.dependsOn`
        * apply objects only after their required APIs or other reconciliation units are ready
        * example
          * Kustomization/infrastructure creates the apps Namespace
          * Kustomization/applications applies Deployments and Services to that Namespace
          * applications.spec.dependsOn waits for infrastructure to become ready
* recovery through Git history
  * create a commit that reverts the desired configuration to an earlier version
  * Flux then reconciles that new Git revision

## Kubernetes API model used by Flux

* core idea
  * Flux uses the Kubernetes API for configuration and controller coordination
  * installing Flux adds custom resource types such as `GitRepository`,
    `Kustomization` and `HelmRelease`
  * the Kubernetes API server stores objects of those types alongside built-in
    objects such as `Deployment` and `Service`
  * each Flux object describes work in its `spec`
    * a `GitRepository` requests a selected Git revision as an artifact
    * a Flux Kustomization identifies the manifests that kustomize-controller must apply
    * a `HelmRelease` requests a Helm release with a selected chart and values
    * digression: downloaded Git files and Helm charts are artifact files stored by
      `source-controller` and served through its in-cluster HTTP Service
        * the Kubernetes source object stores artifact metadata, not the artifact file
  * the corresponding Flux controller reads that description and performs the
    work

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
  * API object: stored record by the Kubernetes control plane
    * example: `Deployment`, `Namespace` or `Secret`
  * workload: an application process running in Pods
      * example: `Deployment/web` in namespace `team-a` is an API object; its Pods run the
        workload

### Status and diagnostics


* location
  * a controller writes its result to the live object's `.status`
    * confirm whether the controller processed the current `.spec`
    * report success, progress or failure
  * the Kubernetes API stores `.status` with the object
  * read it with `kubectl get <kind> <name> -o yaml`
* `.status.conditions`
  * structured controller reports with fields such as `type`, `status`, `reason`
    and `message`
  * condition types depend on the resource
    * examples: `Ready` on many Flux objects, `Complete` on a `Job`
  * not every resource uses conditions; for example, a `Namespace` uses
    `.status.phase`
* determining whether `status` is current
  * `.metadata.generation` is a standard Kubernetes field that changes when the
    object's desired configuration changes
  * many controllers copy the generation they processed to
    `.status.observedGeneration`
  * this convention is used by Flux and many built-in Kubernetes resources, but
    not every resource provides `.status.observedGeneration`
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
    * API type: events.k8s.io/v1
    * Kind: Event
    * in particular: Event refers to another object, but it is not stored as a field in that object
  * example: record controller activity
    * written by controller Pods
    * visible with `kubectl logs`
  * `flux events` queries Kubernetes Events for Flux objects from the Kubernetes
    API server
      * example output
        ```text
        $ flux events --for Kustomization/web-prod -n flux-system
        LAST SEEN  TYPE    REASON                   OBJECT                     MESSAGE
        1m         Normal  ReconciliationSucceeded  Kustomization/web-prod     Applied revision: main@sha1:abc123
        ```

### Custom APIs and controllers

* CustomResourceDefinition (CRD)
  * extends the Kubernetes API with a new resource type
  * defines the resource's API group, versions, name, scope and validation schema
  * after the CRD is installed, the API server can validate and store objects of
    that type
    * in particular: provides storage and validation, but implements no controller behavior
* custom resource
  * one API object of a type registered by a CRD
  * uses the Kubernetes API like a built-in object
  * its `spec` is a declarative description; the object does not perform work
    * `spec` describes the desired state for a custom controller
* custom controller
  * program that reads custom objects and implements the behavior described by
    their `spec`
  * it can create or update Kubernetes objects, call an external API and update
    the custom object's `status`
  * normally runs in a Pod managed by a `Deployment`
* Flux example
  1. Flux installs the `GitRepository` CRD and the `source-controller`
     Deployment
  2. the CRD registers the `GitRepository` API type
  3. `kubectl apply -k flux-setup` creates
     `GitRepository/gitops-flux-workshop` in namespace `flux-system`
    * that object requests the current commit on one Git branch at a one-minute interval
  5. `source-controller` reads the object, downloads the selected commit, packages
     the included files as an artifact and updates the object's `status`
* using existing CRDs
  * many open-source projects provide ready-made CRDs and controllers
    * their Helm chart or installation manifests normally install both
      * example: Flux
* creating a custom API
  * first check whether a built-in type or an established project already meets
    the requirement
  * if a new declarative API is required:
    1. define the CRD schema, scope and supported versions
    2. implement a controller that reads the custom objects and performs the
       described actions
    3. deploy the CRD, controller and required RBAC
        * RBAC = grant the controller permission to read the custom resources, update their
        status and manage the Kubernetes objects that it creates
    4. test validation, reconciliation, upgrades and deletion behavior

## Flux architecture

* Flux controllers run inside Kubernetes
* each controller watches specific Kubernetes API types
* controllers coordinate through specific API objects and their fields
  * example
    * `source-controller` downloads files from Git and records the artifact URL on
      the `GitRepository` object
      * stores the artifact on its filesystem
      * records the artifact revision, digest and URL in the `GitRepository` object's `status`
        * in particular: `GitRepository` object does not contain the artifact files
    * `kustomize-controller` reads that URL and downloads the artifact

### Bootstrap boundary

* installing Flux creates its CRDs and starts its controllers
    * in particular: does not configure a Git repository
* reconciliation starts only after the Kubernetes API contains:
    * a `GitRepository` object that identifies a repository
    * a Flux `Kustomization` object that selects files from that repository
        * in particular
            * manifest committed to Git has no effect until an existing reconciliation selects the directory containing it
            * `kubectl apply -k <directory>` performs a one-time apply

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
  * checks their external sources at the configured intervals
  * downloads files from sources (ex.: Git)
  * stores the result as a fixed artifact and reports it in the source object's
    `status`
  * does not apply application manifests or manage Helm releases

#### Artifact

* file produced by `source-controller`
  * example: `.tar.gz` snapshot of files from one Git commit
  * in particular: not a Kubernetes object and not a container image
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
    * previous artifacts are garbage-collected
      * current defaults keep at most two artifact records after collection
      * previous artifacts become eligible after one minute
      * both values are configurable controller flags; see
        [source-controller options](https://fluxcd.io/flux/components/source/options/)
  * other Flux controllers download the artifact from `source-controller` over HTTP inside the cluster
    * the download URL is stored in the source object's `.status.artifact.url`
        * in particular: the source object's `.status.artifact` does not contain the file
        * example
            ```yaml
            status:
              artifact: # contains metadata that allows another controller to find and verify the file
                revision: main@sha1:abc123 # source revision represented by the artifact
                digest: sha256:012345... # checksum used to verify the downloaded bytes
                size: 18432 # artifact size
                url: http://source-controller.flux-system.svc.cluster.local./gitrepository/flux-system/gitops-flux-workshop/abc123.tar.gz # in-cluster address from which the artifact can be downloaded
            ```
    * a consuming controller:
      1. reads the source object's `.status.artifact`
      2. downloads the file from its `url`
      3. verifies it using its `digest`


#### `GitRepository`
* specifies a Git URL, a commit-selection rule and a check interval
    * every reference rule resolves to one commit
    
      | Reference rule | Selected commit |
      |---|---|
      | `branch: main` | Commit currently referenced by branch `main` |
      | `tag: v2.4.1` | Commit referenced by tag `v2.4.1` |
      | `semver: ">=2.0.0 <3.0.0"` | Commit referenced by the highest matching tag |
      | `commit: abc123...` | The specified commit |
* reconciliation
    * flow
      1. `source-controller` reads the repository URL, reference and interval
      2. it resolves the selected branch, tag or commit
      3. it compares the resolved commit with the current artifact
      4. if the commit changed or the artifact is missing:
         * it checks out the commit in temporary storage
         * it excludes files matched by `.sourceignore` or `spec.ignore`
         * it creates and stores a new artifact
      5. it updates `GitRepository.status`
      6. it checks the repository again after `spec.interval`

#### `HelmRepository`

* points to an HTTP/S Helm chart repository
* `source-controller` downloads `index.yaml`
  * the index maps chart names and versions to chart-package URLs and digests
* a `HelmRelease` selects a chart from the repository through `spec.chart`
  ```yaml
  spec:
    chart:
      spec:
        chart: web
        version: "2.4.1"
        sourceRef:
          kind: HelmRepository
          name: company-charts
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
  * Kubernetes configuration package
    * CI packages a directory of Kubernetes YAML and Kustomize files as a compressed OCI artifact
        * example: directory contains `kustomization.yaml`, `deployment.yaml` and `service.yaml`
    * Flux `OCIRepository` downloads and extracts that package
    * Flux `Kustomization` builds and applies the extracted files
        * in particular: no need for Git artifact
  * Helm chart package
    * a chart publisher packages a Helm chart as an OCI artifact
      * example: the chart contains `Chart.yaml`, `values.yaml` and templates
    * a Flux `OCIRepository` downloads the selected chart version
    * `HelmRelease.spec.chartRef` identifies that `OCIRepository`
        * usually it is `HelmRelease.spec.chart.spec` and `HelmRepository`
    * `helm-controller` installs or upgrades the release from the downloaded chart
      * no `HelmRepository` or generated `HelmChart` object is required
* is an alternative distribution path, not an inherent improvement over Git

#### `Bucket`

* purpose
  * a Flux `Bucket` object tells `source-controller` to download files from an
    object-storage bucket
  * supported storage: Amazon S3, Google Cloud Storage, Azure Blob
    Storage and S3-compatible systems such as MinIO
  * files can contain Kubernetes manifests, Kustomize configuration or a
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
  * example: cluster can authenticate to S3 but not to Git
* change detection
  1. an external system uploads Kubernetes configuration files to an
     object-storage bucket
  2. Flux `Bucket` object specifies the bucket address, authentication and check interval
  3. `source-controller` lists the files in the bucket
     * the storage service returns a name and ETag for each file
        * example
          ```text
          manifests/deployment.yaml  ETag "a1b2"
          manifests/service.yaml     ETag "c3d4"
          ```
     * `source-controller` compares these values with the previous check
     * a changed file name or ETag means that the bucket contents changed
  4. `source-controller` creates a revision from the current file names and ETags
     * example: by hashing the ordered key-and-ETag list
        * in particular: adding, removing or changing a file changes the revision
  5. `source-controller` compares the calculated revision with the last revision
     stored in `Bucket.status`
     * same revision: the bucket did not change, so the existing artifact remains
     * different revision: `source-controller` downloads the files and creates a
       new artifact
  6. `source-controller` records the new artifact's revision, digest and URL in
     `Bucket.status`
  7. a Flux `Kustomization` can use the `Bucket` artifact as its source
    ```
    spec:
        ...
        sourceRef:
            kind: Bucket
            name: company-production-config
    ```

### `kustomize-controller`

* processes Flux `Kustomization` objects
    * each object tells the controller:
      * which source artifact to use
      * which directory to build
      * how often to reconcile
      * whether to prune removed objects or wait for readiness
* reconciliation
    * runs when:
      * the `Kustomization` is created or changed
      * its source produces a new artifact
      * its interval expires
      * an immediate reconciliation is requested
    * processes all objects built from the selected directory as one unit
      * example: Namespace, Deployment and Service
      * the Flux `Kustomization` records the overall result
      * each applied object keeps its own Kubernetes status
* execution model
  * `kustomize-controller` uses the Kustomize Go library
  * it reads and builds the selected source path in memory
    * the build output is a set of Kubernetes objects
  * it does not run `kubectl apply -k`
    * it sends the built objects directly to the Kubernetes API server by using Kubernetes Server-Side Apply
        * the objects are already available in memory
            * in particular: no temporary YAML files or `kubectl` subprocess are required
        * the API server validates the objects
        * the API server creates missing objects and merges changes into existing
          objects
  * `kubectl kustomize <path>` is a local command for inspecting the build output
    * in particular: Flux does not execute this command
* example
  ```yaml
  apiVersion: kustomize.toolkit.fluxcd.io/v1
  kind: Kustomization
  metadata:
    name: production-apps
    namespace: flux-system
  spec:
    interval: 10m
    path: ./environments/production/apps # path inside the source artifact
    prune: true
    wait: true
    sourceRef: # source object in the same namespace
      kind: GitRepository
      name: platform-config
  ```
* Flux `Kustomization` versus Kustomize `kustomization.yaml`
    * Flux `Kustomization`
      * defines continuous reconciliation from a source artifact to a Kubernetes
        cluster
      * selects the source directory
      * configures apply behavior such as interval, pruning and readiness checks
    * Kustomize `kustomization.yaml`
      * defines how files in one directory are combined and transformed
      * lists resources, generators, patches and other Kustomize settings
      * produces the Kubernetes objects that Flux applies
* missing `kustomization.yaml`
  * during reconciliation, `kustomize-controller` checks `spec.path` for a `kustomization.yaml`
    * if the file is missing, `kustomize-controller` generates a temporary one before
      running the Kustomize build
    * Flux has no setting that fails reconciliation only because this file is
      absent
  * limitations
    * resource selection is implicit
      * adding a YAML manifest under the selected tree can add it to the build
    * non-Kubernetes YAML can fail the build unless source ignore rules exclude
      it
    * the generated `kustomization.yaml` only lists discovered manifests as resources
      * it cannot define Kustomize settings such as `namespace`, patches, generators
        or image replacements
    * `kubectl kustomize <path>` cannot reproduce the build without a local
      Kustomize file
    * reviewers cannot inspect one explicit list of managed resources
  * recommendation: commit an explicit `kustomization.yaml` so resource selection and transformations are reviewable and testable before merge

### `helm-controller`

* terminology
  * Helm chart: versioned package containing templates, default values and
    metadata
  * Helm release
    * one named installation of a chart in a Kubernetes cluster
    * each successful install or upgrade creates a release revision
    * Helm normally stores the revision records as Kubernetes Secrets
        * the record contains the chart, values, rendered manifests and release status
            * the Secret contains one field:
              ```yaml
              apiVersion: v1
              kind: Secret
              metadata:
                name: sh.helm.release.v1.web-prod.v3
                namespace: production
              type: helm.sh/release.v1
              data:
                release: <encoded and compressed Helm release record>
              ```
              * after decoding and decompressing `data.release`, the release record contains:
                * the chart and its template files
                * the values used for the release
                * release metadata and status
                * one rendered manifest string containing all Kubernetes objects
                    * rendered manifest combines multiple objects as YAML documents
                      ```yaml
                      ---
                      # Source: web/templates/service.yaml
                      apiVersion: v1
                      kind: Service
                      metadata:
                        name: web
                      ...
                      ---
                      # Source: web/templates/deployment.yaml
                      apiVersion: apps/v1
                      kind: Deployment
                      metadata:
                        name: web
                      ...
                      ```
        * Helm uses it for upgrades, rollbacks, history and uninstall
            * Helm needs persistent release state because it has no separate server or database
  * Flux `HelmRelease`: custom Kubernetes API object that declares the desired
    chart, values and Helm action policies
  * Flux `HelmChart`: custom Kubernetes API object that declares which chart
    and version `source-controller` must obtain and store as an artifact
    * when `HelmRelease.spec.chart` is used, `helm-controller` creates the
      `HelmChart`
      * OCI alternative
        * `HelmRelease.spec.chartRef` can refer directly to an `OCIRepository`
        * the OCI artifact then replaces the intermediate `HelmChart` in this flow
    * `HelmChart.status.artifact` identifies the chart package produced by
      `source-controller`
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
        chart: webapp # chart name in HelmRepository index.yaml
        version: "2.4.1" # selected chart version
        sourceRef:
          kind: HelmRepository
          name: company-charts # HelmRepository in the same namespace
    values: # overrides the chart's default value
      replicaCount: 3
    valuesFrom: # load additional values from Secrets or ConfigMaps
      - kind: ConfigMap
        name: web-prod-values # external values in the same namespace
    driftDetection:
      mode: enabled # detect and correct changes to installed resources
  ```
* example HTTP/S Helm repository reconciliation: upgrade from `2.4.0` to `2.4.1`
  1. state before this reconciliation run:
     * the chart repository already contains `webapp-2.4.1.tgz`
     * its `index.yaml` maps chart `webapp` version `2.4.1` to that package URL
       and digest
     * publication of the package and index occurs outside Flux
     * `HelmRepository/company-charts` and `HelmRelease/web-prod` already exist in
       the Kubernetes API
     * the cluster contains the last successful Helm release for version `2.4.0`
     * Git contains both manifests, and a new commit changes only
       `spec.chart.spec.version` in the `HelmRelease/web-prod` manifest from
       `2.4.0` to `2.4.1`
  2. `kustomize-controller` applies the changed `HelmRelease` manifest
    * it is included in a directory managed by a Flux `Kustomization`
  3. `source-controller` reconciles `HelmRepository/company-charts` after an
     object change or its configured interval
     * it downloads `index.yaml`
     * it stores the index as an artifact
     * it writes the artifact URL to `HelmRepository.status.artifact`
  4. `helm-controller` reads the changed `HelmRelease`.
     * it creates or updates a `HelmChart` object that requests chart `webapp`,
       version `2.4.1`, from `HelmRepository/company-charts`
  5. `source-controller` reconciles the `HelmChart`.
     * it reads the repository index artifact
     * it finds and downloads `webapp-2.4.1.tgz`
     * it stores that package as an artifact
     * it writes the package URL and digest to `HelmChart.status.artifact`
  6. `helm-controller` reads that status, downloads the chart package from the
     internal `source-controller` URL and renders its templates with the values
     from `HelmRelease/web-prod`
  7. `helm-controller` compares the requested chart and values with the Helm release
     stored in the cluster
     * no stored release: run Helm install
     * different chart or values: run Helm upgrade
     * same chart and values: do not run install or upgrade
     * in this example: version and chart digest differ, so it runs Helm upgrade
  9. `helm-controller` updates `HelmRelease/web-prod.status` after each
     reconciliation run
* drift detection
  * detects manual changes to objects created by a Helm release
  * requires `HelmRelease.spec.driftDetection.mode: enabled`
    * if the field is omitted, drift detection is disabled
  * during a later reconciliation, when no install or upgrade is required:
    1. `helm-controller` reads the rendered manifests from the current Helm
       release revision
    2. it parses each manifest into a desired Kubernetes object
    3. `helm-controller` reads the corresponding live object from the Kubernetes API
    4. it sends the stored manifest to the API server as a Server-Side Apply request
       with `dryRun=All`
       * the API server calculates the object that would result from the apply
       * the API server returns that calculated object without storing it
    5. `helm-controller` compares:
       * the live object read in step 3
       * the calculated object returned in step 4
    6. if the objects differ, drift exists
       * `helm-controller` corrects the changed objects directly with Server-Side
         Apply
       * it does not run Helm upgrade because the chart, values and stored Helm
         release did not change

### `notification-controller`

* provides two separate functions
  * incoming webhooks
    * a `Receiver` accepts a webhook from a Git provider, registry or another
      external system
    * after validating the request, it asks the configured Flux source objects
      to reconcile immediately instead of waiting for their next interval
  * outgoing notifications
    * an `Alert` selects Events reported by Flux controllers
    * a `Provider` sends the selected Events to an external system such as
      Slack, Microsoft Teams or another webhook endpoint
  * in particular: it does not fetch Git, render manifests or apply workloads

#### `Receiver`: inbound webhook

* purpose
  * reduce the delay between an external change and the next source check
  * example: a GitHub push requests immediate reconciliation of a
    `GitRepository` instead of waiting for its interval
* polling remains the fallback when webhook delivery fails
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
    secretRef: # identifies a Kubernetes Secret in the Receiver namespace
      name: github-webhook-token
    resources:
      - apiVersion: source.toolkit.fluxcd.io/v1
        kind: GitRepository
        name: platform-config
  ```
* after the `Receiver` becomes ready, `Receiver.status.webhookPath` contains its
  generated path
  * example: `/hook/bed6d00b...`
  * the path identifies this specific `Receiver`
* expose the `webhook-receiver` Kubernetes Service through an Ingress,
  HTTPRoute or external load balancer
  * example external host: `https://flux-webhook.example.com`
    * combine the external host with `status.webhookPath`
      * example payload URL:
        `https://flux-webhook.example.com/hook/bed6d00b...`
* configure the shared webhook token
  1. generate a random token
  2. store the token under the `token` key in a Kubernetes Secret
  3. set `Receiver.spec.secretRef.name` to the name of that Secret
     * the `Receiver` and Secret must be in the same namespace
  4. enter the same token in GitHub's **Webhook secret** field
* HMAC verification
  * HMAC is a keyed message-authentication code
  * it proves that the sender knew the shared token and that the request body was
    not changed
  * it does not encrypt the request body
  1. GitHub calculates an HMAC-SHA256 value from the request body and shared token
    * result proves two things:
      * sender knows the secret key
      * request body was not changed after signing
  2. GitHub sends the value in `X-Hub-Signature-256`
  3. `notification-controller` calculates the expected value with the Secret token
  4. `notification-controller` compares the received signature with its calculated
     signature
     * if the signatures differ, it rejects the request
     * if the signatures match, it accepts the request as authentic
  5. `notification-controller` checks the GitHub event type against
     `Receiver.spec.events`
     * a matching event triggers reconciliation of the objects listed in
       `Receiver.spec.resources`
     * a non-matching event does not trigger reconciliation

#### `Provider` and `Alert`: outbound notification

* purpose
  * send selected Events from Flux controllers to an external notification
    system
  * examples:
    * a production reconciliation failed
    * a new revision was applied successfully
* `Provider` declares the external system that receives notifications
  * `spec.type` selects the provider type, such as Slack or Microsoft Teams
  * `spec.address` identifies the destination endpoint when required
  * `spec.secretRef` identifies the Kubernetes Secret containing credentials
    when required
* `Alert` defines which controller Events are sent
  * `spec.eventSources` selects the Flux objects whose Events are considered
  * `spec.eventSeverity` selects the minimum severity to send
      * Flux controllers attach `info` or `error` severity to notification events
        * this is Flux event metadata
        * it is distinct from the Kubernetes Event `Normal` or `Warning` type
  * `spec.providerRef` identifies the `Provider` used to deliver them
* example: send error events from one production reconciliation to Slack

  ```yaml
  apiVersion: notification.toolkit.fluxcd.io/v1beta3
  kind: Provider
  metadata:
    name: operations-slack
    namespace: flux-system
  spec:
    type: slack # use the Slack notification integration
    address: https://slack.com/api/chat.postMessage # Slack API endpoint
    channel: operations # destination Slack channel
    secretRef: # Secret containing the Slack authentication token
      name: slack-bot-token
  ---
  apiVersion: notification.toolkit.fluxcd.io/v1beta3
  kind: Alert
  metadata:
    name: production-errors
    namespace: flux-system
  spec:
    providerRef: # Provider used to send matching Events
      name: operations-slack
    eventSeverity: error # send only error-level Events
    eventSources:
      - kind: Kustomization
        name: web-prod # observe Events from this Flux Kustomization
  ```
* authentication depends on the external API
  * GitHub signs each webhook request with the shared webhook token
    * `notification-controller` recalculates the HMAC signature and verifies it
  * Slack requires an API bearer token
    * `notification-controller` reads the token from `Provider.spec.secretRef`
    * it includes the token in the Slack API request
  * these tokens are unrelated and must be stored in separate Secrets

### Image controllers

* optional components
  * `image-reflector-controller` scans a container registry and selects an image
    according to an `ImagePolicy`
    * writes the result to `ImagePolicy.status.latestRef`
  * `image-automation-controller` writes the selected image reference to marked
    fields in YAML files in Git
    * flow
        1. scans YAML files under `ImageUpdateAutomation.spec.update.path`
        1. finds the $imagepolicy markers
        1. reads the selected image from each referenced ImagePolicy
        1. replaces the marked YAML value
        1. commits and pushes the change
    * in particular: file does not need to be a Kubernetes Deployment
        * example
            ```
            apps:
              app1: ghcr.io/company/app1:1.2.0 # {"$imagepolicy": "flux-system:app1-prod"}
              app2: ghcr.io/company/app2:3.4.0 # {"$imagepolicy": "flux-system:app2-prod"}
              app3: ghcr.io/company/app3:1.5.0 # {"$imagepolicy": "flux-system:app3-prod"}
            ```
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
    image: ghcr.io/company/payment-api # container image repository to scan
    interval: 5m
  ---
  apiVersion: image.toolkit.fluxcd.io/v1
  kind: ImagePolicy
  metadata:
    name: payment-api-prod
    namespace: flux-system
  spec:
    imageRepositoryRef:
      name: payment-api # use tags found by ImageRepository/payment-api
    policy:
      semver:
        range: ">=2.0.0 <3.0.0" # select the highest matching 2.x version
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
      name: platform-config # Git repository containing the manifests
    update:
      path: ./apps/payment-api # update marked fields under this directory
    git:
      commit:
        author: # author recorded on automated commits
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
* management model
  * Flux is controller-oriented
    * users combine several Kubernetes objects to define the delivery flow
    * `GitRepository` obtains files, `Kustomization` applies manifests and
      `HelmRelease` manages a Helm release
    * each object has its own reconciliation interval, status and dependencies
    * Flux does not require one top-level object representing the complete
      application
  * Argo CD is application-oriented
    * an `Application` connects source configuration with a target cluster and
      namespace
    * Argo CD presents the managed resources, health, differences and sync status
      under that `Application`
    * users normally synchronize and troubleshoot the deployment through the
      `Application`
  * Flux can still use one `Kustomization` per application
    * this grouping is optional
    * Argo CD uses `Application` as its primary user-facing model
* applying new revisions
  * Flux automatically applies a new source revision unless reconciliation is
    suspended
  * Argo CD can apply revisions automatically
    * without automated synchronization, it reports the difference and waits
      for a user or API request
* correcting manual changes
  * a Flux `Kustomization` corrects changes during periodic reconciliation
  * a Flux `HelmRelease` corrects changes when drift detection is enabled
  * Argo CD corrects changes automatically when self-healing is enabled
* deleting resources removed from the desired state
  * Flux requires `Kustomization.spec.prune: true`
  * Argo CD automated pruning requires
    `Application.spec.syncPolicy.automated.prune: true`
  * an Argo CD manual synchronization can also request pruning
* installation topology
  * Flux controllers are normally installed in each managed cluster
  * Argo CD is often installed in one management cluster that manages other
    registered clusters
  * Argo CD can also manage its installation cluster
* user interface
  * Flux uses Kubernetes objects, the Flux CLI, Events and controller logs
  * Argo CD provides an API, CLI and web interface with resource trees, diffs,
    health and synchronization history
* authorization
    * Flux
        * Git repository permissions determine who can make persistent changes to the
          desired Flux configuration
        * Kubernetes RBAC controls
            * who can change live Flux objects directly
                * if an object is managed from Git, Flux later restores the version stored
                  in Git
                * if an object is not managed from Git, the direct change remains
            * what Flux controllers can change
                1. `Kustomization.spec.serviceAccountName` and
                        `HelmRelease.spec.serviceAccountName` select a Kubernetes ServiceAccount
                1. controller uses Kubernetes impersonation to act as that ServiceAccount
                    during reconciliation
    * Argo CD
        * Argo CD RBAC controls who can view, create, change, synchronize or delete
            Argo CD applications
        * `AppProject` defines what applications in that project are allowed to
          deploy
          * in particular
            * which repositories they may read configuration from
            * which clusters and namespaces they may deploy to
            * which Kubernetes resource types they may create
          * every Argo CD `Application` belongs to an `AppProject`
          * example: the `payments` project can allow its applications to:
            * read configuration from `company/payments-config`
            * deploy to the `payments` namespace
            * create only `Deployment`, `Service` and `ConfigMap` objects
        * the Argo CD application controller applies resources with credentials for
          the target cluster
          * Kubernetes RBAC for those credentials provides the final authorization at
              the target cluster

### Deployment dependencies

* general
  * Flux
    * dependencies are defined between Flux `Kustomization` objects
    * `spec.dependsOn` identifies the required `Kustomization` objects
    * Flux waits until every dependency reports `Ready`
  * Argo CD
    * resources in one `Application` can be ordered with sync waves
    * Argo CD applies earlier waves before later waves
    * separate `Application` objects normally reconcile independently
    * Argo CD has no direct `Application.spec.dependsOn` equivalent

* example: deploy workloads after shared infrastructure
  * Flux
    * `Kustomization/infrastructure` applies the infrastructure
    * `Kustomization/applications` applies the workloads
    * the workload `Kustomization` declares:
      ```yaml
      spec:
        dependsOn:
          - name: infrastructure
      ```
    * Flux waits for `Kustomization/infrastructure` to report `Ready`
  * Argo CD
    * place the infrastructure and workloads in one `Application`
    * assign infrastructure resources to an earlier sync wave:
      ```yaml
      metadata:
        annotations:
          argocd.argoproj.io/sync-wave: "-1"
      ```
    * workloads use the default wave `0`
    * Argo CD applies the infrastructure wave first and waits for it to become
      healthy before applying the workload wave

### Deployment approval

* Flux normally treats an accepted Git commit as approved desired state
  * source detection triggers reconciliation without a second deployment approval
  * `Kustomization.spec.suspend: true` pauses future reconciliation
    * Flux does not create a native pending deployment with an approve button
    * => suspension is not an approval workflow
* Argo CD can separate detection from deployment
  * the Application controller calculates the difference after merge
  * with automated sync disabled, the Application remains unsynchronized until a
    user or API client starts synchronization
  * this is useful when 
    * deployment authorization is separate from code approval
    * production changes must wait for a maintenance window or coordinated release
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
  * if Flux stops working in one cluster, other clusters continue to reconcile
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

* choose Flux when platform infrastructure and workloads need independent
  in-cluster reconciliation with Kubernetes-native dependencies and RBAC
* Argo CD can manage the same infrastructure, but it must be represented through
  Applications and Argo CD policies
* choose Argo CD when operators need a centralized application inventory,
  visual differences and an optional manual synchronization step after merge
* Flux can support those operating practices only with additional user-interface,
  inventory or approval tooling

## Workshop flow: Git to Kubernetes

1. `kubectl apply -k flux-setup` creates the initial `GitRepository` and Flux
   `Kustomization` objects in the Kubernetes API
   * both objects use the `flux-system` namespace
     * `flux-system` is the default namespace used by Flux installations for Flux
       controllers and bootstrap configuration
2. `GitRepository/gitops-flux-workshop` specifies:
   * repository URL
   * `main` branch
   * one-minute check interval
3. `source-controller` checks the repository
   * `branch: main` is a selection rule whose result can change
   * for each check, the controller resolves that rule to the exact commit
     currently referenced by `main`
4. `source-controller` downloads that commit to temporary storage and creates a
   compressed artifact from the included files
   * the artifact contains the included repository files
   * the controller stores the artifact under its configured storage path and
     serves it through its in-cluster HTTP Service
   * it records the commit, digest and URL in
     `GitRepository.status.artifact`
   * the controller removes the temporary Git checkout after it creates the
     artifact
5. `kustomize-controller` reads `Kustomization/nginx` from the Kubernetes API.
   * `spec.sourceRef.name: gitops-flux-workshop` selects the source object
   * `spec.path: ./apps/nginx` selects a path relative to the root of that
     source artifact
6. `kustomize-controller` downloads the artifact from its internal URL, verifies
   the digest and extracts it into a temporary directory.
7. `kustomize-controller` builds the selected path.
   * build means read `apps/nginx/kustomization.yaml` and produce the final
     Kubernetes manifests
   * the output contains the Namespace, ConfigMap, Deployment and Service
   * the output exists in controller memory; it is not stored as temporary
     Kubernetes objects
8. `kustomize-controller` resolves the apply order.
   * it applies `Namespace/nginx` before the namespaced objects
   * no separate namespace reconciliation is required
9. `kustomize-controller` sends each desired object to the Kubernetes API as a
   server-side apply dry-run.
   * the API server performs validation, defaulting, admission and managed-field
     conflict checks
   * `dryRun=All` makes the API server return the result without storing the
     object
   * the dry-run result tells the controller whether a real server-side apply is
     required; this is not a text comparison of YAML files
   * when a Flux-managed field differs or an object is missing, the controller
     sends the real server-side apply request
   * when no relevant field differs, the controller does not change the stored
     object
   * because `spec.prune: true`, it deletes previously managed objects that are
     absent from the build output
10. built-in Kubernetes controllers process the applied objects.
   * example: the Deployment controller creates a ReplicaSet, and the ReplicaSet
     controller creates the requested Pods
   * the Service can exist before the Pods; it gains endpoints when matching Pods
     become ready
11. because `spec.wait: true`, `kustomize-controller` checks the health of all
    reconciled objects until they are ready or `spec.timeout` expires.
    * ready means that Flux's health check for that object reports success; for a
      Deployment, the rollout must become available
    * if `spec.wait` is omitted or `false`, the controller does not wait for all
      applied objects to become healthy before it completes the reconciliation
    * `false` is the default
12. `kustomize-controller` records the applied revision, managed-object inventory
    and conditions in `Kustomization/nginx.status`.
13. the controller deletes its extracted temporary files.
14. source changes, API watch events, intervals, retries and manual requests
    trigger later reconciliations

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

   * command

     ```bash
     kubectl -n <release-namespace> describe helmrelease <release-name>
     ```

   * example `Ready` condition

     ```yaml
     - type: Ready
       status: "False"
       reason: InstallFailed
       message: Helm install failed because Deployment/payment-api was not ready
     ```

   * interpretation
     * read the four fields as one tuple
     * `type: Ready` asks whether the desired Helm release is installed and
       current
     * `status: "False"` answers no
     * `reason: InstallFailed` classifies the failed operation
     * `message` names the immediate cause
     * a condition value has meaning only with its type
       * example: `Drifted=False` means that no drift was detected

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
   * do not manually delete the `HelmRelease` as a routine troubleshooting step
     * `helm-controller` treats deletion as a request to uninstall the Helm
       release
     * if a parent Flux `Kustomization` manages the manifest, it can recreate the
       `HelmRelease` later
     * recreation does not prevent the intervening uninstall and reinstall cycle

* [Flux troubleshooting cheatsheet](https://fluxcd.io/flux/cheatsheets/troubleshooting/)
