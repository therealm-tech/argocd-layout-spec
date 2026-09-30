# Contributing

Changes go through pull requests on
[therealm-tech/argocd-layout-spec](https://github.com/therealm-tech/argocd-layout-spec).
A change to a rule updates [SPEC.md](SPEC.md) and [examples/](examples/) in the
same pull request.

## Development setup

The only tool needed is [pre-commit](https://pre-commit.com/), which installs
the hooks' own dependencies:

```sh
uv tool install pre-commit
```

```sh
pre-commit install
```

## Running the tests

There is no test suite. The checks are the pre-commit hooks, which lint the
specification's YAML and the example layout.

## Pre-commit hooks

Hooks must pass before a commit is pushed.

```sh
pre-commit run --all-files
```

```sh
pre-commit run <hook-id> --all-files
```

| Hook | Checks | Fix |
| --- | --- | --- |
| `trailing-whitespace`, `end-of-file-fixer` | whitespace | fixed automatically, re-stage |
| `check-yaml` | YAML parses | fix the syntax |
| `check-added-large-files`, `check-merge-conflict`, `detect-private-key` | accidental commits | remove the file or the marker |
| `yamllint` | YAML style, per [.yamllint.yaml](.yamllint.yaml) | block style, no leading `---` |
| `actionlint` | GitHub Actions workflows | fix the workflow |
| `no-co-authors` | commit message has no `Co-Authored-By` / `Generated with` line | rewrite the message |

`--no-verify` and `SKIP=` are not the fix: correct the file, or change the
configuration in the same pull request and say why.

## Continuous integration

| Workflow | Triggers on | What it does | Reproduce locally |
| --- | --- | --- | --- |
| [quality.yaml](.github/workflows/quality.yaml) | every pull request, push to `main` | `pre-commit run --all-files` | `pre-commit run --all-files` |
| [security.yaml](.github/workflows/security.yaml) | every pull request, push to `main`, daily, manual | `trivy fs` on the repository, fails on fixable `HIGH`/`CRITICAL`, reports to code scanning | `trivy fs .` |

Both are required to merge. [Dependabot](.github/dependabot.yaml) keeps the
action pins up to date.

## Submitting a change

- Commit subjects are imperative and lowercase, without a trailing period.
- CI is green and the documentation is updated in the same pull request.
