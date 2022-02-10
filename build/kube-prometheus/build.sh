#!/usr/bin/env bash
#
# This script should be run from the root of the argocd-apps repo
# This script takes path to cluster folder in customer-kubernetes-config-repo as
# arg $1. It assumes there is a cluster-name-vars.jsonnet file in that folder
# and will put all the new manifests in kube-promehteus dir in that folder.
# For example you might give it ../kubernetes-config-enableit/kam.obmondo.com/
# and it will look for the file
# ../kubernetes-config-enableit/kam.obmondo.com/kam.obmondo.com-vars.jsonnet and
# put the resulting manifests in
# ../kubernetes-config-enableit/kam.obmondo.com/kube-prometheus

set -euo pipefail

declare -i apply=0
declare dry_run='' \
        cluster_dir=''

function usage() {
  cat <<EOF
${0} [-a|--apply] [-c|--create-namespaces] <CLUSTER>

Compile kube-prometheus manifests from jsonnet template.

Arguments:
  -a|--apply
    Apply the resulting manifests.
  -c|--create-namespaces
    Automatically create any namespaces that doesn't exist when applying.
  --dry-run=<client|server>
    Dry run.
EOF
}

while (( $# > 0 )); do
  case "${1}" in
    -a|--apply)
      apply=1
      ;;
    --dry-run=*)
      [[ "${1}" =~ --dry-run=(.+) ]]
      dry_run="${BASH_REMATCH[1]}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "${cluster_dir}" ]] || ! [[ "${1}" =~ ^[a-z0-9.-]+$ ]]; then
        echo "Invalid argument ${1}"
        exit 2
      fi
      cluster_dir="${1}"
      ;;
  esac
  shift
done

if ! [[ "${cluster_dir}" ]]; then
  echo "missing argument cluster_dir"
  exit 2
fi

cluster=$(basename "$cluster_dir")
cluster_jsonnet="${cluster_dir}/${cluster}-vars.jsonnet"

if [ ! -e "${cluster_jsonnet}" ]
then
  echo "no such variable file ${cluster_jsonnet}"
  exit 2
fi

# sanity checks
if ! tmp=$(jsonnet --version); then
  echo "missing the program 'jsonnet'"
  exit 2
fi
if ! [[ "${tmp}" =~ v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "unable to parse jsonnet version ('${tmp}')"
  exit 2
fi

declare -i _version=$(( (BASH_REMATCH[1]*10**6) + (BASH_REMATCH[2]*10**3) + BASH_REMATCH[3] ))
if (( _version < 18000 )); then
  echo "jsonnet version too old; aborting"
  exit 2
fi

# Make sure to use project tooling
OUTDIR="${cluster_dir}/kube-prometheus"

# Make sure to start with a clean 'manifests' dir
rm -rf "${OUTDIR:?}/"
mkdir -p "${OUTDIR}/setup"

# Calling gojsontoyaml is optional, but we would like to generate yaml, not json
#jsonnet -J vendor -m manifests "${1-example.jsonnet}" | xargs -I{} sh -c 'cat {} | gojsontoyaml > {}.yaml' -- {}

RELEASE=$(jsonnet "${cluster_jsonnet}" | jq -r .kube_prometheus_version)
JSONNET_LIB_PATH="build/kube-prometheus/libraries/${RELEASE}/vendor"
if ! [ -e "${JSONNET_LIB_PATH}" ]; then
  if [[ -d "build/kube-prometheus/libraries/${RELEASE}" ]]; then
    echo 'Release dir exists; exiting'
    exit 73
  fi

  echo "INFO: '${JSONNET_LIB_PATH}' doesn't exist; executing jsonnet-bundler"
  jb init
  jb install "github.com/prometheus-operator/kube-prometheus/jsonnet/kube-prometheus@${RELEASE}"
  mkdir "build/kube-prometheus/libraries/${RELEASE}"
  mv vendor "build/kube-prometheus/libraries/${RELEASE}/"
  mv jsonnetfile.json jsonnetfile.lock.json "build/kube-prometheus/libraries/${RELEASE}/"
fi

echo "INFO: compiling jsonnet files into '${OUTDIR}'"

# remove previous output to avoid leftover files
rm -f "${OUTDIR}/*"
mkdir -p "${OUTDIR}"

# shellcheck disable=SC2016
jsonnet -J \
        "${JSONNET_LIB_PATH}" \
        --ext-code-file vars="${cluster_jsonnet}" \
        -m "${OUTDIR}" \
        "common-template.jsonnet" |
  while read -r f; do
    "$(go env GOPATH)/bin/gojsontoyaml" < "${f}" > "${f}.yaml"
    rm "${f}"
  done

if (( apply )); then
  kubectl_args=()
  if [[ "$dry_run" ]]; then
    kubectl_args+=("--dry-run=${dry_run}")
  fi
  kubectl apply "${kubectl_args[@]}" -f "${OUTDIR}"
fi
