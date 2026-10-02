# Argo CD layout specification

The key words MUST, MUST NOT, SHOULD and MAY are to be interpreted as described
in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

## 1. Scope

This specification defines the **shape of the files** of a GitOps repository
deploying applications with Argo CD: where they live, what they contain, and how
they combine. It does not define how they are wired into Argo CD: any wiring
that honours the rules below is conforming. §12 describes one that uses only
native Argo CD features.

Out of scope: operations (version alignment between apps, promotion between
environments, how and when Applications are synced), how namespaces are
created and shared, secrets and AppProjects. An app MAY name the namespace it
is deployed to and its Helm release names; nothing else of namespaces is the
layout's business.

## 2. Vocabulary

- **Environment**: the smallest unit of deployment for a set of applications.
  An environment spans one or more clusters.
- **Cluster**: a Kubernetes cluster. A cluster hosts one or more environments.
- **Placement**: an environment on one of its clusters. Every instance of the
  environment is deployed once per placement.
- **App**: something installable: a set of sources, their configuration and
  additional manifests.
- **Catalog**: the set of apps installable in any environment. A layout has at
  most one catalog.
- **Cluster app**: an app defined by a cluster, installable only in the
  environments placed on that cluster.
- **Instance**: an app installed in an environment, under a name. An app MAY be
  installed several times in one environment.
- **Local instance**: an instance whose app is defined by the environment
  itself, neither in the catalog nor by a cluster.
- **Layer**: one level of configuration of an instance (§5).
- **Resource identity**: `<group>/<kind>/<name>[_<namespace>]`, where
  `<group>` is the API group of the resource's `apiVersion` (`core` when it
  has none), `<kind>` its `kind` verbatim, `<name>` its `metadata.name`, and
  `_<namespace>` is present if and only if the resource sets
  `metadata.namespace`.
- **Property**: a named scalar value, injected into apps at render time (§9).

## 3. Layout

```
catalog/
  properties.yaml
  apps/<app>/                           # app directory
clusters/<cluster>/
  properties.yaml
  apps/<app>/                           # app directory: a cluster app
  overrides/<app>/                      # app directory: a catalog app on this cluster
envs/<env>/
  env.yaml
  properties.yaml
  instances/<instance>/                 # app directory
  clusters/<cluster>/
    properties.yaml
    instances/<instance>/               # app directory
```

An **app directory** has the same shape at every layer:

```
app.yaml
values/<source>.yaml
manifests/
  kustomization.yaml
  resources/<resource identity>.yaml
  patches/<resource identity>.yaml
```

1. Every file and directory above is OPTIONAL, except `env.yaml` in an
   environment.
2. `clusters/` and `envs/` live in one repository, under one root directory.
   `catalog/` lives either under the same root or in a repository of its own,
   where it MAY be any directory. A layout consumes a separate catalog at a
   single revision: its files, values files and manifests all come from it.
   The specification governs `properties.yaml`, `apps/`, `clusters/` and
   `envs/` only; the roots MAY hold anything else, such as the wiring.
3. Environment, cluster, app, instance and source names MUST be
   [RFC 1123 labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names).
4. An environment is declared by its `env.yaml`. A cluster is declared by its
   directory under `clusters/` or by being listed in an `env.yaml`. An
   instance is declared in its `env.yaml`. An app is declared by its default
   layer. A source of an instance is declared by being named under `sources`
   in the `app.yaml` of any of the instance's layers, on any of its
   environment's clusters, those it is disabled on included, even with a
   `null` value.
5. A directory or file that does not match a declared environment, cluster,
   app, instance or source is an error (orphan), placeholders such as
   `.gitkeep` included. Orphans are checked against declared names, not
   against the merged configuration: a values file whose source a higher layer
   removes is unused, not an orphan.

## 4. Apps and instances

1. An environment declares its instances in `env.yaml` (§10). Nothing is
   installed that is not declared there.
2. An instance name is unique within an environment.
3. An instance refers to its app by one of:
   - `app: <app>`: a catalog app or a cluster app;
   - `local: true`: a local instance, whose app is defined in
     `instances/<instance>/`, where `app.yaml` MUST exist;
   - nothing: the app named like the instance.
4. A cluster app MUST NOT have the name of a catalog app. Two clusters MAY
   each define a cluster app of the same name: an instance referring to that
   name resolves to a different app on each cluster.
5. On every cluster of the environment, each instance MUST resolve to an app,
   unless the instance is disabled on that cluster (§10).
6. Any app, whatever its provenance, MAY be instantiated several times in an
   environment.
7. A local instance keeps its configuration in the layout; its sources MAY
   point to any repository.

## 5. Layers

An instance is configured by the following layers, from lowest to highest
precedence. Each higher layer is applied on top of the ones below.

| Provenance | Default | Environment | Cluster | Placement |
| --- | --- | --- | --- | --- |
| Catalog app | `catalog/apps/<app>/` | `envs/<e>/instances/<i>/` | `clusters/<c>/overrides/<app>/` | `envs/<e>/clusters/<c>/instances/<i>/` |
| Cluster app | `clusters/<c>/apps/<app>/` | `envs/<e>/instances/<i>/` | — | `envs/<e>/clusters/<c>/instances/<i>/` |
| Local instance | — | `envs/<e>/instances/<i>/` | — | `envs/<e>/clusters/<c>/instances/<i>/` |

1. The **lowest layer** of an instance is its first layer in that order.
2. The cluster layer is keyed by app and applies to every instance of that app
   on the cluster, over their environment layers. What must differ between two
   instances on one cluster belongs in the placement layer.
3. A cluster app has no cluster layer: its definition is its default layer.
   `clusters/<c>/overrides/<app>/` for a cluster app of `<c>` is an orphan.
4. There is no inheritance between environments: an environment reads only
   its own layers and the layers below them.
5. `envs/<e>/clusters/<c>/instances/<i>/` MUST NOT exist when `<i>` is
   disabled on `<c>`.

## 6. `app.yaml`

```yaml
namespace: rook-ceph
sources:
  chart:
    type: helm
    repoURL:
      property: rookCharts
    repository: release
    chart: rook-ceph
    targetRevision: "v1.20.8"
    releaseName: rook-ceph
    properties:
      image.registry: imageRegistry
manifests:
  properties:
    external-secrets.io/ClusterSecretStore/vault:
      /spec/provider/vault/server: vaultUrl
```

`namespace` is OPTIONAL: the namespace the instance is deployed to. Without
it, the wiring chooses one. Like every field, it MAY be set or changed by any
layer; so MAY `releaseName`. A wiring that derives either from the instance
name changes it when the instance is renamed, so renaming an instance whose
data must survive first pins both in its environment layer.

### 6.1 Sources

1. `sources` is a map from source name to source. An app MAY have no source
   when it has manifests.
2. The specification defines these source fields. A wiring MAY support more;
   they merge like the others.

   | Field | Content |
   | --- | --- |
   | `type` | the tool rendering the source: `helm`, `kustomize`, `jsonnet` or `directory` |
   | `repoURL` | the base of the repository URL |
   | `repository` | OPTIONAL; the repository URL is `repoURL`, then `/`, then `repository` |
   | `chart` | the chart name, for a `helm` source from a chart repository |
   | `path` | the path in the repository, for any other source |
   | `targetRevision` | the chart version or the Git revision, as a string: an unquoted `1.10` is the number 1.1 in YAML |
   | `releaseName` | OPTIONAL, for a `helm` source: its Helm release name; without it, the wiring chooses one |
   | `properties` | the property mapping of the source (§9.3) |

3. `repoURL` is either a literal string or a map with a single `property` key
   naming a property. It is the only source field that MAY take a property.
4. After all layers are merged, every source MUST have `type`, `repoURL`,
   `targetRevision`, and exactly one of `chart` and `path`.

### 6.2 Merge

`app.yaml` files merge across layers:

1. Maps are merged recursively.
2. Any other value, lists included, is replaced.
3. `null` removes the key. `sources.<name>: null` removes a source.

A higher layer MAY change any field of a source, its origin included. The
configuration of the lower layers still applies to the new origin. Since maps
merge, a layer changing a source's nature also sets to `null` what no longer
fits: `chart` or `path`, a `repository` meant for the old origin, a
`releaseName` when it is no longer `helm`, and the `properties` mapping, whose
shape depends on the type (§9.3). Lists replace: a layer giving
`application.syncOptions` or `application.ignoreDifferences` restates the
entries of the layers below that it keeps.

### 6.3 Application settings

`application` is OPTIONAL and holds settings of the Argo CD Application that
deploys the instance, merged across layers like the rest of the file:

| Field | Content |
| --- | --- |
| `syncOptions` | Argo CD sync options, such as `ServerSideApply=true` for CRDs too large for a client-side apply; an option replaces the wiring's option of the same name |
| `ignoreDifferences` | Argo CD `ignoreDifferences` entries, for fields a controller rewrites after the sync, such as injected CA bundles |

No other field is allowed: when and how an Application syncs is operations.

## 7. Values

1. `values/<source>.yaml` holds the Helm values of the source `<source>`. It
   exists only in a layer where the source, as merged up to that layer, is a
   `helm` source. A higher layer that changes the source's type leaves it
   unused.
2. The values files of a source are passed to Helm in layer order, lowest
   first. They merge by Helm's own rules.

## 8. Manifests

1. `manifests/` is a Kustomize `Component`, in every layer. The wiring stacks
   the components of an instance's layers, in layer order, on an empty base.
   A component in a separate catalog is fetched from the catalog's repository;
   the others MUST be in the same repository as the base.
2. `kustomization.yaml` has `apiVersion`, `kind: Component`, `resources` and
   `patches`, and no other field: `namespace`, `namePrefix`, `images`,
   generators and the like change resource identities. `resources` lists every
   file of `resources/`, and `patches` every file of `patches/`, each as a
   single `path`.
3. A file of `resources/` holds exactly one resource, in a single YAML
   document, and is named after its identity.
4. A file of `patches/` is a strategic merge patch named after the identity of
   its target. The target MUST be present once the lower layers and the
   resources of the patch's own layer are applied, and the patch MUST carry
   the target's `apiVersion`: Kustomize matches a patch on its version too. A patch containing
   `$patch: delete` removes the resource. On a custom resource, a strategic
   merge patch replaces lists as a whole: Kustomize knows no merge key for
   them.
5. A layer adds a resource by putting it in `resources/`, and changes, replaces
   or removes one with a patch. It cannot add a resource whose identity is
   already present: Kustomize rejects the duplicate before applying patches.
6. `patches/` targets only the manifests of the layout, never the resources
   rendered from the sources.
7. A resource whose identity does not depend on the instance exists once per
   cluster: a cluster-scoped resource, a resource of the layout's manifests
   that sets its namespace or that goes to a namespace `namespace` sets, or a
   resource a source renders with a fixed name, such as a CRD. At most one instance per cluster, all environments included,
   MAY keep such a resource once its layers are applied; an instance whose
   layers delete it does not count. Operators and other cluster-wide apps
   therefore usually belong to a single environment per cluster.

## 9. Properties

### 9.1 Definition

1. `properties.yaml` is a flat map from property name to scalar value.
   Property names match `[a-zA-Z][a-zA-Z0-9]*`.
2. Properties follow the order of the layers, from lowest to highest
   precedence: `catalog/properties.yaml`, `envs/<e>/properties.yaml`,
   `clusters/<c>/properties.yaml`, `envs/<e>/clusters/<c>/properties.yaml`.
   A higher file replaces the value of a property of a lower one; `null`
   removes it.
3. Properties are global: they apply to every instance of the placement,
   whatever its provenance.

### 9.2 Reference

1. A property is a whole value: it replaces an entire field. The only
   concatenation is the one of `repoURL` and `repository` (§6.1.2).
2. A property is injected only through the native input Argo CD offers for the
   tool rendering the target: the source's `repoURL`, `helm.parameters`,
   `directory.jsonnet.extVars` and `directory.jsonnet.tlas`, or
   `kustomize.patches`. Values files and manifests never reference a property.
3. Referencing an undefined property is an error.
4. A property keeps its YAML type wherever the target allows it: a string
   stays a string in a Helm parameter, and a number stays a number in a
   Kustomize patch. Jsonnet variables are strings: a Jsonnet program parses
   the ones it needs as numbers or booleans.
5. A property name is a string once YAML has parsed it: `y`, `n`, `on`, `off`,
   `yes`, `no` and `null` MUST be quoted, or avoided, both as keys of
   `properties.yaml` and as values of a mapping.

### 9.3 Mapping

The mapping says where each property lands. It lives in `app.yaml` and merges
across layers like the rest of the file; setting an entry to `null` removes it.

| Where | Shape | Target |
| --- | --- | --- |
| `sources.<s>.properties` of a `helm` source | a map from Helm parameter name (`image.registry`) to property | `helm.parameters` |
| `sources.<s>.properties` of a `jsonnet` source | maps `extVars` and `tlas`, each from variable name to property | `directory.jsonnet.extVars`, `directory.jsonnet.tlas` |
| `sources.<s>.properties` of a `kustomize` source | a map from resource identity to a map from JSON pointer to property | `kustomize.patches` (`op: replace`) |
| `manifests.properties` | a map from resource identity to a map from JSON pointer to property | `kustomize.patches` of the manifests (`op: replace`) |

1. A `directory` source takes no mapping.
2. The resource targeted by `manifests.properties` MUST exist once all layers
   are applied, and so MUST the field each JSON pointer designates: the
   property replaces a value, and never adds one.
3. A mapped value is applied after every layer: a Helm parameter overrides
   every values file, and a Kustomize patch applies after every component. A
   higher layer that needs to set a mapped field itself removes the mapping
   entry.

## 10. `env.yaml`

```yaml
clusters:
  prod-eu: {}
  prod-us:
    disabled:
      - ceph-ssd
instances:
  cert-manager: {}
  ceph-hdd:
    app: rook-ceph-cluster
  ceph-ssd:
    app: rook-ceph-cluster
  whoami:
    local: true
```

1. `clusters` lists the clusters the environment is placed on. An environment
   without clusters is placed nowhere, and deploys nothing.
   `envs/<e>/clusters/<c>/` exists only for a listed cluster. A cluster with
   no `clusters/<c>/` directory is a cluster without specific configuration.
2. `clusters.<c>.disabled` lists instances not installed on that cluster. Each
   MUST be a declared instance.
3. `instances` declares the instances of the environment (§4). `app` and
   `local` are mutually exclusive.

## 11. Errors and limitations

A conforming layout has none of the following:

1. a name that is not an RFC 1123 label (§3.3);
2. an orphan file or directory (§3.5, §5.3, §5.5);
3. an instance that does not resolve on one of its clusters and is not
   disabled there (§4.5);
4. a cluster app named like a catalog app (§4.4);
5. a local instance without `envs/<e>/instances/<i>/app.yaml` (§4.3);
6. an incomplete source after merge, a `targetRevision` that is not a string,
   a property in a field other than `repoURL`, or a `chart` or `releaseName`
   on a source that is not `helm` (§6.1);
7. a values file in a layer where its source is not `helm` (§7.1);
8. a `kustomization.yaml` that is not a `Component`, uses another field, or
   does not list exactly the files of `resources/` and `patches/` (§8.2);
9. a manifest file whose name does not match its identity, or that holds more
   than one YAML document (§8.3);
10. a patch whose target is absent or has another `apiVersion`, or a resource
    added twice (§8.4, §8.5);
11. an app holding resources of a fixed identity instantiated several times on
    one cluster (§8.7);
12. a reference to an undefined property, or a property that is not a scalar
    (§9.1, §9.2.3);
13. a mapping on a `directory` source (§9.3.1);
14. a `manifests.properties` target that does not exist (§9.3.2);
15. an undeclared instance in `disabled`, or an instance with both `app` and
    `local` (§10);
16. an `application` field other than `syncOptions` and `ignoreDifferences`
    (§6.3).

The layout does not support:

- two resources of one app with the same identity;
- resources whose name contains `_`, since `_` separates the namespace in an
  identity, and resources whose name contains a character a file name cannot
  hold on the platforms in use, such as `:` on Windows;
- properties that are part of a value, other than a `repoURL`;
- patches on resources rendered from a source.

## 12. Native wiring

This section is informative. A layout can be assembled by Argo CD alone:

1. The layout root is a Helm chart: a `Chart.yaml`, a `templates/` directory
   and an empty Kustomize base, next to `clusters/` and `envs/`.
2. One Application per cluster renders that chart, with the cluster name as a
   parameter.
3. The chart reads the layout with `.Files`: it selects the environments
   placed on its cluster, expands their instances, reads each layer (a missing
   file reads as empty), merges `app.yaml` and the properties, and fails the
   render on any error of §11 it can detect. It checks the catalog, the
   environments placed on its cluster and that cluster's directory, so that a
   mistake blocks only the clusters it concerns. It cannot detect duplicate
   keys in a YAML file, a JSON pointer naming a missing field (§9.3.2), nor
   the resources §8.7 describes when they are cluster-scoped or rendered by a
   source; those surface when the instance's Application renders or syncs.
   It cannot see a file no rendered cluster reads either, such as an
   environment placed nowhere, or one whose `env.yaml` is misnamed.
4. It emits one Application per instance and placement: the merged sources,
   each with its tool set explicitly so that Argo CD never guesses it, the
   values files of every layer through `ref` sources, the Helm parameters,
   Jsonnet variables and Kustomize patches of the mapping, and the manifest
   components of every layer on the empty base.
5. It names what it emits so that nothing collides: the Application
   `<env>.<instance>.<cluster>` (`.` cannot appear in a name of the layout).
   An instance without `namespace` goes to `<env>-<instance>`, and a Helm
   source without `releaseName` is released as `<env>-<instance>`, whatever
   the number of Helm sources: adding a source never renames another one's
   release, and an app with several Helm sources names them. Names
   a chart derives from its release, such as its ClusterRoles, are then
   unique across environments. Two instances installing the same release in
   the same namespace of a cluster fail the render, and so does a release
   name longer than Helm's 53 characters.
6. The Application names it emits need Argo CD 3.0 or later, whose default
   annotation-based resource tracking takes names longer than a label's 63
   characters. A Helm source whose repository URL has no scheme is an OCI
   registry, which Argo CD reaches through a repository or a credential
   template registered with OCI enabled and matching that URL. The layout's own directories, `catalog/`, `clusters/` and
   `envs/`, never collide with the names Helm reserves at a chart's root.
7. A separate catalog is a Helm chart too, published at a version and tagged
   `v<version>` in Git. Its `Chart.yaml` names the Git repository in
   `sources`, and the catalog's directory there in a `layout/catalog-path`
   annotation when it is not the root. The layout chart declares it as a
   dependency named `catalog` and reads its files through `.Subcharts`; the generated
   Applications fetch its values files through a `ref` source and its
   manifests as remote Kustomize components, both at that tag. Upgrading the
   catalog is bumping the dependency and refreshing `Chart.lock`. Nothing but
   this convention ties the package to the tag: they are published together,
   from the same commit. Kustomize fetches the remote components itself,
   twice per render of an Application; a catalog that is not public needs
   credentials Argo CD hands to Kustomize, which may be only those of the
   Application's own source repository.

Everything is rendered by Helm and Kustomize; no plugin is involved.
[examples/](examples/) implements this wiring with its catalog alongside, and
[examples-confidential/](examples-confidential/) with the catalog of
[examples/](examples/) consumed as a dependency.
