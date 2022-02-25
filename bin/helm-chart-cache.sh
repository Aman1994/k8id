#!/bin/bash

set -euo pipefail

export HELM_EXPERIMENTAL_OCI=1

while getopts p:r:u: flag
do
    case "${flag}" in
        p) password=${OPTARG};;
        r) registry=${OPTARG};;
        u) username=${OPTARG};;
        *) >&2 echo "Invalid flag '$flag', exiting"; exit 1
    esac
done

helm registry login "$registry" --username "$username" --password-stdin <<< "$password"

find argocd-helm-charts -maxdepth 1 -mindepth 1 -type d | while read -r path; do
  echo "### Attempting dep up for upstream for $path ###"
  bash helm-dep-up.sh -u true -p "$path" -r "$registry"
  if [ -d "$path/charts" ]; then
    find "${path}/charts" -maxdepth 1 -name '*.tgz' | while read -r tarfile; do
      tgzfile=$(basename "$tarfile");
      version=$(echo "$tgzfile" | grep -o "v*[0-9]\{1\}[0-9]*.+*[0-9].*" | sed 's/\.tgz//')
      # The logic behind this if statement is sometimes version is just a single
      # digit and while pulling the chart for such they fail hence append 0.0
      if [ -z "$version" ]; then
        version=$(echo "$tgzfile" | grep -o "v*[0-9]\{1\}.tgz" | sed 's/\.tgz//')
        version=$version.0.0
      fi
      chartname=${tgzfile/-$version.tgz}
      echo "### Pulling chart $chartname:$version ###"
      if ! helm pull "${registry}/${chartname}:${version}" > /dev/null; then
        echo "### Saving and pushing chart $chartname:$version ###"
        helm create "$tarfile" "${registry}/${chartname}:${version}"
        helm push "${registry}/${chartname}:${version}"
        echo "###  Doing dep up for ghcr for $path ###"
        bash helm-dep-up.sh -u false -p "$path" -r "$registry";
        echo "### Checking for changes in $path/Chart.lock file for $CI_COMMIT_SHA:$path/Chart.lock ###"
        if git diff "$CI_COMMIT_SHA:$path/Chart.lock" "$path/Chart.lock" | grep '^[+]' | grep -Ev '^(--- a/|\+\+\+ b/)' | grep -qE '\+generated.*'; then
            echo "### Some changes happened in $path/Chart.lock file ###"
            cat "$path/Chart.lock"
            exit 1
        fi
      fi
    done
  fi
done