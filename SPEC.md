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
environments), namespaces, secrets and AppProjects.

## 2. Vocabulary

- **Environment**: the smallest unit of deployment for a set of applications.
  An environment spans one or more clusters.
- **Cluster**: a Kubernetes cluster. A cluster hosts one or more environments.
- **Placement**: an environment on one of its clusters. Every instance of the
  environment is deployed once per placement.
- **App**: something installable: a set of sources, their configuration and
  additional manifests.
- **Catalog**: the set of apps installable in any environment. A layout has
  exactly one catalog.
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
4. A cluster is declared by being listed in an `env.yaml`. An instance is
   declared in its `env.yaml`. An app is declared by its default layer.
5. A directory or file that does not match a declared environment, cluster,
   app, instance or source is an error (orphan). Orphans are checked against
   declared names, not against the merged configuration: a values file whose
   source a higher layer removes is unused, not an orphan.

## 4. Apps and instances

1. An environment declares its instances in `env.yaml` (§10). Nothing is
   installed that is not declared there.
2. An instance name is unique within an environment.
3. An instance refers to its app by one of:
   - `app: <app>`: a catalog app or a cluster app;
   - `local: true`: a local instance, whose app is defined in
     `instances/<instance>/`;
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
sources:
  chart:
    type: helm
    repoURL:
      property: rookCharts
    repository: release
    chart: rook-ceph-cluster
    targetRevision: v1.20.7
    properties:
      image.registry: imageRegistry
manifests:
  properties:
    external-secrets.io/ClusterSecretStore/vault:
      /spec/provider/vault/server: vaultUrl
```

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
   | `targetRevision` | the chart version or the Git revision |
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
configuration of the lower layers still applies to the new origin.

## 7. Values

1. `values/<source>.yaml` holds the Helm values of the source `<source>`. It
   exists only for a `helm` source.
2. The values files of a source are passed to Helm in layer order, lowest
   first. They merge by Helm's own rules.

## 8. Manifests

1. `manifests/` is a Kustomize `Component`, in every layer. The wiring stacks
   the components of an instance's layers, in layer order, on an empty base.
   A component in a separate catalog is fetched from the catalog's repository;
   the others MUST be in the same repository as the base.
2. `kustomization.yaml` lists the files of `resources/` and `patches/`, all of
   them, and nothing else. It uses no other field: `namespace`, `namePrefix`,
   `images`, generators and the like change resource identities and are not
   allowed.
3. A file of `resources/` holds exactly one resource and is named after its
   identity.
4. A file of `patches/` is a strategic merge patch named after the identity of
   its target. The target MUST be present once the lower layers are applied.
   A patch containing `$patch: delete` removes the resource.
5. A layer adds a resource by putting it in `resources/`, and changes, replaces
   or removes one with a patch. It cannot add a resource whose identity is
   already present: Kustomize rejects the duplicate before applying patches.
6. `patches/` targets only the manifests of the layout, never the resources
   rendered from the sources.
7. An app instantiated several times in one placement MUST NOT have
   cluster-scoped manifests: every instance would declare the same resource.

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

### 9.3 Mapping

The mapping says where each property lands. It lives in `app.yaml` and merges
across layers like the rest of the file; setting an entry to `null` removes it.

| Where | Shape | Target |
| --- | --- | --- |
| `sources.<s>.properties` of a `helm` source | a map from Helm parameter name (`image.registry`) to property | `helm.parameters` |
| `sources.<s>.properties` of a `jsonnet` source | maps `extVars` and `tlas`, each from variable name to property | `directory.jsonnet.extVars`, `directory.jsonnet.tlas` |
| `sources.<s>.properties` of a `kustomize` source | a map from resource identity to a map from JSON pointer to property | `kustomize.patches` (`op: add`) |
| `manifests.properties` | a map from resource identity to a map from JSON pointer to property | `kustomize.patches` of the manifests (`op: add`) |

1. A `directory` source takes no mapping.
2. The resource targeted by `manifests.properties` MUST exist once all layers
   are applied.
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

1. `clusters` lists the clusters the environment is placed on.
   `envs/<e>/clusters/<c>/` exists only for a listed cluster.
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
6. an incomplete source after merge (§6.1.4);
7. a values file for a non-`helm` source (§7.1);
8. a `kustomization.yaml` using a field other than its resources, patches and
   components (§8.2);
9. a manifest file whose name does not match its identity (§8.3);
10. a patch whose target is absent (§8.4);
11. an app with cluster-scoped manifests instantiated several times in one
    placement (§8.7);
12. a reference to an undefined property (§9.2.3);
13. a mapping on a `directory` source (§9.3.1);
14. a `manifests.properties` target that does not exist (§9.3.2);
15. an undeclared instance in `disabled`, or an instance with both `app` and
    `local` (§10).

The layout does not support:

- two resources of one app with the same identity;
- resources whose name contains `_`, since `_` separates the namespace in an
  identity;
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
   render on any error of §11 it can detect.
4. It emits one Application per instance and placement: the merged sources,
   the values files of every layer through `ref` sources, the Helm parameters,
   Jsonnet variables and Kustomize patches of the mapping, and the manifest
   components of every layer on the empty base.
5. A separate catalog is a Helm chart too, published at a version and tagged
   with it in Git. The layout chart declares it as a dependency and reads its
   files through `.Subcharts`; the generated Applications fetch its values
   files through a `ref` source and its manifests as remote Kustomize
   components, both at the tag of that version. Upgrading the catalog is
   bumping the dependency.

Everything is rendered by Helm and Kustomize; no plugin is involved.
[examples/](examples/) implements this wiring with its catalog alongside, and
[examples-confidential/](examples-confidential/) with the catalog of
[examples/](examples/) consumed as a dependency.
