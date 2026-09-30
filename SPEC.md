# Argo CD layout specification

The key words MUST, MUST NOT, SHOULD and MAY are to be interpreted as described
in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
[RFC 8174](https://www.rfc-editor.org/rfc/rfc8174).

## 1. Scope

This specification defines the **shape of the files** of a GitOps repository
deploying applications with Argo CD: where they live, what they contain, and how
they combine. It does not define how they are wired into Argo CD
(ApplicationSets, app-of-apps, one Argo CD or several): any wiring that honours
the rules below is conforming.

Out of scope: operations (version alignment between apps, promotion between
environments), namespaces, secrets and AppProjects.

## 2. Vocabulary

- **Environment**: the smallest unit of deployment for a set of applications.
  An environment spans one or more clusters.
- **Cluster**: a Kubernetes cluster. A cluster hosts one or more environments.
- **Placement**: an environment on one of its clusters. It is what gets
  deployed.
- **App**: something installable: a set of sources, their configuration and
  additional manifests.
- **Catalog**: the set of apps installable in any environment. A layout has
  exactly one catalog.
- **Cluster app**: an app defined by a cluster, installable only in the
  environments placed on that cluster.
- **Instance**: an app installed in an environment, under a name. An app MAY be
  installed several times in one environment.
- **Local instance**: an instance of an app that is neither in the catalog nor
  a cluster app.
- **Layer**: one level of configuration of an instance (§5).
- **Property**: a named scalar value, set per layer, injected into apps at
  render time (§9).

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
  resources/<group>/<kind>/<name>[@<namespace>].yaml
  patches/<group>/<kind>/<name>[@<namespace>].yaml
```

1. Every file and directory above is OPTIONAL, except `env.yaml` in an
   environment.
2. `catalog/`, `clusters/<cluster>/` and `envs/<env>/` are each self-contained
   and MAY live in separate repositories. How they reference each other is up
   to the wiring.
3. Environment, cluster, app, instance and source names MUST be
   [RFC 1123 labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#dns-label-names).
4. A directory or file that does not match a declared environment, cluster,
   app, instance or source is an error (orphan).

## 4. Apps and instances

1. An environment declares its instances in `env.yaml` (§10). Nothing is
   installed that is not declared there.
2. An instance name is unique within an environment.
3. An instance refers to its app by one of:
   - `app: <app>`: a catalog app or a cluster app;
   - `path`: a local instance (§4.7);
   - nothing: the app named like the instance.
4. A cluster app MUST NOT have the name of a catalog app. An app name
   therefore resolves to at most one app on a given cluster.
5. On every cluster of the environment, each instance MUST resolve to an app,
   unless the instance is disabled on that cluster (§10).
6. Any app, whatever its provenance, MAY be instantiated several times in an
   environment.
7. The `path` of a local instance points to an app directory, inside or
   outside the repository. That directory is the instance's environment layer.
   If it is not `instances/<instance>/` itself, `instances/<instance>/` MUST
   NOT exist.

## 5. Layers

An instance is configured by the following layers, from lowest to highest
precedence. Each higher layer is applied on top of the ones below.

| Provenance | Default | Environment | Cluster | Placement |
| --- | --- | --- | --- | --- |
| Catalog app | `catalog/apps/<app>/` | `envs/<e>/instances/<i>/` | `clusters/<c>/overrides/<app>/` | `envs/<e>/clusters/<c>/instances/<i>/` |
| Cluster app | `clusters/<c>/apps/<app>/` | `envs/<e>/instances/<i>/` | — | `envs/<e>/clusters/<c>/instances/<i>/` |
| Local instance | — | the directory at `path` | — | `envs/<e>/clusters/<c>/instances/<i>/` |

1. The **lowest layer** of an instance is its first existing layer in that
   order.
2. The cluster layer is keyed by app and applies to every instance of that app
   on the cluster, over their environment layers. The environment and
   placement layers are keyed by instance.
3. A cluster app has no cluster layer: its definition is its default layer.
   `clusters/<c>/overrides/<app>/` for a cluster app of `<c>` is an orphan.
4. There is no inheritance between environments: an environment reads only
   its own layers and the layers below them.

## 6. `app.yaml`

```yaml
sources:
  chart:
    type: helm
    repoURL:
      property: chartRegistry
    repository: rook/charts
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
2. A source has these fields:

   | Field | Content |
   | --- | --- |
   | `type` | the tool rendering the source: `helm`, `kustomize`, `jsonnet` or `directory` |
   | `repoURL` | the base of the repository URL |
   | `repository` | OPTIONAL, appended to `repoURL` with a `/` |
   | `chart` | the chart name, for a `helm` source from a chart repository |
   | `path` | the path in the repository, for any other source |
   | `targetRevision` | the chart version or the Git revision |
   | `properties` | the property mapping of the source (§9.3) |

3. `repoURL` is either a literal string or a map with a single `property` key
   naming a property. It is the only source field that MAY take a property.
4. After all layers are merged, every source MUST have `type`, `repoURL`,
   `targetRevision`, and exactly one of `chart` and `path`.

### 6.2 Merge

`app.yaml` files merge across layers like Helm values:

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
3. Values files MUST NOT reference properties.

## 8. Manifests

1. `manifests/` is a Kustomize directory. In the lowest layer of an instance it
   is a `Kustomization`; in every other layer it is a `Component`. The wiring
   stacks the components on the base in layer order.
2. `kustomization.yaml` lists the files of `resources/` and `patches/`. No
   other file is referenced.
3. A file of `resources/` holds exactly one resource. Its path is derived from
   the resource:
   - `<group>` is the API group of `apiVersion`, or `core` when there is none;
   - `<kind>` is `kind`, verbatim;
   - `<name>` is `metadata.name`;
   - `@<namespace>` is present if and only if the resource sets
     `metadata.namespace`, and holds it.
4. A file of `patches/` is a strategic merge patch named after the resource it
   targets, by the same rule. The target MUST be a resource of a lower layer.
   A patch containing `$patch: delete` removes the resource.
5. A layer adds a resource by putting it in `resources/`, changes one with a
   patch, and replaces one by deleting it and adding the new one.
6. Patches target only the manifests of the layout, never the resources
   rendered from the sources.
7. Manifests MUST NOT reference properties.

## 9. Properties

### 9.1 Definition

1. `properties.yaml` is a flat map from property name to scalar value.
2. Properties are defined in four layers, from lowest to highest precedence:
   `catalog/properties.yaml`, `envs/<e>/properties.yaml`,
   `clusters/<c>/properties.yaml`, `envs/<e>/clusters/<c>/properties.yaml`.
   A higher layer replaces the value of a property of a lower layer.
3. Properties are global: they apply to every instance of the placement,
   whatever its provenance.

### 9.2 Reference

1. A property is a whole value, never a fragment: it replaces an entire field,
   and is never concatenated with anything by the layout.
2. A property is injected only through the native input Argo CD offers for the
   tool rendering the target: the source's `repoURL`, `helm.parameters`,
   `directory.jsonnet.extVars` and `directory.jsonnet.tlas`, or
   `kustomize.patches`. No file of the layout references a property.
3. Referencing an undefined property is an error.

### 9.3 Mapping

The mapping says where each property lands. It lives in `app.yaml` and merges
across layers like the rest of the file.

| Where | Key | Target |
| --- | --- | --- |
| `sources.<s>.properties` of a `helm` source | a Helm parameter name (`image.registry`) | `helm.parameters` |
| `sources.<s>.properties` of a `jsonnet` source | `extVars.<name>` or `tlas.<name>` | `directory.jsonnet.extVars`, `directory.jsonnet.tlas` |
| `sources.<s>.properties` of a `kustomize` source | `<group>/<kind>/<name>[@<namespace>]`, then a JSON pointer | `kustomize.patches` (`op: replace`) |
| `manifests.properties` | `<group>/<kind>/<name>[@<namespace>]`, then a JSON pointer | `kustomize.patches` of the manifests (`op: replace`) |

1. The value of every mapping entry is a property name.
2. A `directory` source takes no mapping.
3. The resource targeted by `manifests.properties` MUST exist once all layers
   are applied.

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
    path: instances/whoami
  status-page:
    path:
      repoURL: https://github.com/example/status-page
      path: deploy
      targetRevision: main
```

1. `clusters` lists the clusters the environment is placed on.
   `envs/<e>/clusters/<c>/` exists only for a listed cluster.
2. `clusters.<c>.disabled` lists instances not installed on that cluster. Each
   MUST be a declared instance.
3. `instances` declares the instances of the environment (§4). `app` and `path`
   are mutually exclusive.
4. `path` is either a path relative to the environment directory or a map with
   `repoURL`, `path` and `targetRevision`.

## 11. Errors

A conforming layout has none of the following:

1. an orphan file or directory (§3.4, §5.3);
2. an instance that does not resolve on one of its clusters and is not
   disabled there (§4.5);
3. a cluster app named like a catalog app (§4.4);
4. an incomplete source after merge (§6.1.4);
5. a values file for a missing or non-`helm` source (§7.1);
6. a manifest file whose path does not match its content (§8.3);
7. a patch whose target is not a resource of a lower layer (§8.4);
8. a reference to an undefined property (§9.2.3);
9. a `manifests.properties` target that does not exist (§9.3.3);
10. a disabled instance that is not declared (§10.2).
