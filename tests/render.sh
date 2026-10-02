#!/usr/bin/env bash
# Renders each example layout for every one of its clusters and compares it
# with the layout's rendered/ directory, renders tests/features/ the same way,
# then checks that each layout under tests/errors/ fails to render with the
# message in its `expected-error` file. `--update` rewrites the rendered/
# directories instead of comparing.
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
update=false
[[ "${1:-}" == "--update" ]] && update=true

# Helm logs every symbolic link it follows on stderr; examples-confidential
# shares its templates with examples through one.
quiet_symlinks() {
  "$@" 2> >(grep -v 'found symbolic link' >&2)
}

render() {
  quiet_symlinks helm template layout "$1" -f "$2" --set "cluster=$3"
}

# A test layout holds layout files only: run it with the example chart.
with_chart() {
  local work
  work=$(mktemp -d)
  cp -R "$repo_root/examples/Chart.yaml" "$repo_root/examples/values.yaml" "$repo_root/examples/templates" "$work/"
  cp -R "$1"/. "$work/"
  echo "$work"
}

failures=0

check_rendered() {
  local name=$1 chart_dir=$2 values=$3 rendered_dir=$4 cluster=$5
  local expected="$rendered_dir/$cluster.yaml" actual
  if ! actual=$(render "$chart_dir" "$values" "$cluster"); then
    echo "FAIL: $name/$cluster does not render"
    failures=$((failures + 1))
  elif $update; then
    mkdir -p "$rendered_dir"
    printf '%s\n' "$actual" >"$expected"
    echo "updated ${expected#"$repo_root/"}"
  elif diff -u "$expected" <(printf '%s\n' "$actual"); then
    echo "ok: ${expected#"$repo_root/"}"
  else
    echo "FAIL: ${expected#"$repo_root/"} differs, rerun with --update if intended"
    failures=$((failures + 1))
  fi
}

for layout in examples examples-confidential; do
  dir="$repo_root/$layout"
  if grep -q '^dependencies:' "$dir/Chart.yaml"; then
    quiet_symlinks helm dependency build "$dir" >/dev/null
  fi
  for cluster_dir in "$dir"/clusters/*/; do
    check_rendered "$layout" "$dir" "$dir/values-lint.yaml" "$dir/rendered" "$(basename "$cluster_dir")"
  done
done

features=$(with_chart "$repo_root/tests/features")
check_rendered features "$features" "$repo_root/examples/values-lint.yaml" "$repo_root/tests/features/rendered" lab-1
rm -rf "$features"

$update && exit "$failures"

for case_dir in "$repo_root"/tests/errors/*/; do
  case_name=$(basename "$case_dir")
  work=$(with_chart "$case_dir")
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
