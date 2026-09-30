# argocd-layout-spec

A specification of the file layout of a GitOps repository that deploys
applications with Argo CD.

## Description

The specification defines where the files of such a repository live and how
they combine: a catalog of apps with a default configuration, and environments
and clusters that select apps from it, add their own, and override any part of
their configuration — values, manifests and chart origin — without copying what
they do not change.

It covers the shape of the files only. How they are wired into Argo CD
(ApplicationSets, app-of-apps, one Argo CD or several) is left to each
repository, as are operations such as promotion between environments.

## Getting started

### Prerequisites

None: the specification is Markdown and YAML.

### Usage

1. Read [SPEC.md](SPEC.md).
2. Browse [examples/](examples/), a layout with a catalog, a connected cluster,
   an air-gapped cluster and two environments. Its chart versions and values
   are illustrative.
3. Lay out a GitOps repository after them, then write the Argo CD wiring that
   reads it.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
