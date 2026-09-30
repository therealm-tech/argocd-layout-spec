# layout

Renders the Argo CD Applications of one cluster from the layout around it.

This directory is an example layout following [SPEC.md](../SPEC.md), and the
Helm chart that wires it into Argo CD using native features only.

- The catalog app [layout](catalog/apps/layout/) is an ApplicationSet creating
  one Application per cluster registered in Argo CD, each rendering this chart
  with the cluster's name. The `platform` environment installs it on `lab-1`,
  the cluster running Argo CD, so the layout manages its own wiring.
  Bootstrapping applies it once by hand:
  `kubectl apply -k catalog/apps/layout/manifests`.
- [templates/](templates/) reads the layout with `.Files`, merges the layers of
  every instance placed on that cluster, and emits one Application per
  instance. A layout error fails the render.
- [rendered/](rendered/) holds the Applications the chart produces for each
  example cluster; `tests/render.sh` checks it stays in sync.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| argocdNamespace | string | `"argocd"` | Namespace Argo CD reads Applications from. |
| cluster | string | `nil` | Name of the cluster to render, identical in Argo CD and in the layout. |
| layout | object | `{"path":null,"repoURL":null,"targetRevision":null}` | Where the generated Applications read the layout from. |
| layout.path | string | `nil` | Path of the layout root inside the repository. |
| layout.repoURL | string | `nil` | Git URL of the repository holding the layout. |
| layout.targetRevision | string | `nil` | Revision of the layout the generated Applications track. |
| project | string | `"default"` | Argo CD project of the generated Applications. |
