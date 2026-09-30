#!/usr/bin/env bash
# Renders each example layout for every one of its clusters into the layout's
# rendered/ directory, then checks that each layout under tests/errors/ fails to
# render with the message in its `expected-error` file.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
layouts=(examples examples-confidential)

# Helm logs every symbolic link it follows on stderr; examples-confidential
# shares its templates with examples through one.
quiet_symlinks() {
  "$@" 2> >(grep -v 'found symbolic link' >&2)
}

render() {
  quiet_symlinks helm template layout "$1" -f "$2" --set "cluster=$3"
}

failures=0

for layout in "${layouts[@]}"; do
  dir="$repo_root/$layout"
  if grep -q '^dependencies:' "$dir/Chart.yaml"; then
    quiet_symlinks helm dependency build "$dir" >/dev/null
  fi
  mkdir -p "$dir/rendered"
  for cluster_dir in "$dir"/clusters/*/; do
    cluster=$(basename "$cluster_dir")
    expected="$dir/rendered/$cluster.yaml"
    if render "$dir" "$dir/values-lint.yaml" "$cluster" >"$expected"; then
      echo "ok: $layout/rendered/$cluster.yaml"
    else
      echo "FAIL: $layout/$cluster does not render"
      failures=$((failures + 1))
    fi
  done
done

for case_dir in "$repo_root"/tests/errors/*/; do
  case_name=$(basename "$case_dir")
  work=$(mktemp -d)
  cp -R "$repo_root/examples/Chart.yaml" "$repo_root/examples/values.yaml" "$repo_root/examples/templates" "$work/"
  cp -R "$case_dir"/. "$work/"
  expected_error=$(cat "$case_dir/expected-error")
  if output=$(render "$work" "$repo_root/examples/values-lint.yaml" lab-1 2>&1); then
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
