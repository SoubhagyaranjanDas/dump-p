#!/usr/bin/env bash
# Regenerate nested kustomization.yaml files under gateways/ and routes/
# so Flux (kustomize build ./) picks up any *.yaml merged without hand-editing lists.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

write_leaf() {
  local dir="$1"
  [[ -d "$dir" ]] || return 0
  local files=()
  mapfile -t files < <(
    find "$dir" -maxdepth 1 -type f \( -name '*.yaml' -o -name '*.yml' \) ! -name 'kustomization.yaml' -printf '%f\n' 2>/dev/null | LC_ALL=C sort -u
  )
  if [[ ${#files[@]} -eq 0 ]]; then
    rm -f "$dir/kustomization.yaml"
    return 0
  fi
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    local x
    for x in "${files[@]}"; do
      echo "  - $x"
    done
  } >"$dir/kustomization.yaml"
}

write_mid() {
  local mid="$1"
  [[ -d "$mid" ]] || return 0
  local subs=()
  local name
  mapfile -t names < <(find "$mid" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | LC_ALL=C sort -u)
  for name in "${names[@]}"; do
    write_leaf "$mid/$name"
    [[ -f "$mid/$name/kustomization.yaml" ]] && subs+=("$name")
  done
  if [[ ${#subs[@]} -eq 0 ]]; then
    rm -f "$mid/kustomization.yaml"
    return 0
  fi
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    local s
    for s in "${subs[@]}"; do
      echo "  - $s"
    done
  } >"$mid/kustomization.yaml"
}

write_mid gateways
write_mid routes

# Root: include gateways/routes only if they have a kustomization.
root_res=()
[[ -f gateways/kustomization.yaml ]] && root_res+=(gateways)
[[ -f routes/kustomization.yaml ]] && root_res+=(routes)
{
  echo "apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "kind: Kustomization"
  if [[ ${#root_res[@]} -eq 0 ]]; then
    echo "resources: []"
  else
    echo "resources:"
    local r
    for r in "${root_res[@]}"; do
      echo "  - $r"
    done
  fi
} >kustomization.yaml.tmp
mv kustomization.yaml.tmp kustomization.yaml
