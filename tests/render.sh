#!/usr/bin/env bash
# Renders the example layout for every cluster and compares it with
# examples/rendered/, then checks that each layout under tests/errors/ fails to
# render with the message in its `expected-error` file. `--update` rewrites
# examples/rendered/ instead of comparing.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
examples="$repo_root/examples"
lint_values="$examples/values-lint.yaml"
update=false
[[ "${1:-}" == "--update" ]] && update=true

render() {
  helm template layout "$1" -f "$lint_values" --set "cluster=$2"
}

failures=0

for cluster_dir in "$examples"/clusters/*/; do
  cluster=$(basename "$cluster_dir")
  expected="$examples/rendered/$cluster.yaml"
  if $update; then
    mkdir -p "$examples/rendered"
    render "$examples" "$cluster" >"$expected"
    echo "updated rendered/$cluster.yaml"
  elif diff -u "$expected" <(render "$examples" "$cluster"); then
    echo "ok: rendered/$cluster.yaml"
  else
    echo "FAIL: rendered/$cluster.yaml differs, rerun with --update if intended"
    failures=$((failures + 1))
  fi
done

$update && exit 0

for case_dir in "$repo_root"/tests/errors/*/; do
  case_name=$(basename "$case_dir")
  work=$(mktemp -d)
  cp -R "$examples/Chart.yaml" "$examples/values.yaml" "$examples/templates" "$work/"
  cp -R "$case_dir"/. "$work/"
  expected_error=$(cat "$case_dir/expected-error")
  if output=$(render "$work" lab-1 2>&1); then
    echo "FAIL: errors/$case_name rendered without error"
    failures=$((failures + 1))
  elif [[ "$output" != *"$expected_error"* ]]; then
    echo "FAIL: errors/$case_name failed with an unexpected message:"
    echo "$output"
    failures=$((failures + 1))
  else
    echo "ok: errors/$case_name"
  fi
  rm -rf "$work"
done

exit "$failures"
