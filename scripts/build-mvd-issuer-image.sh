#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <mvd-repo-path> <target-image-ref>" >&2
  exit 1
fi

mvd_repo="$1"
target_image="$2"

if [[ ! -d "$mvd_repo" ]]; then
  echo "MVD repo path not found: $mvd_repo" >&2
  exit 1
fi

(
  cd "$mvd_repo"
  ./gradlew build
  ./gradlew -Ppersistence=true dockerize
)

docker tag issuerservice:latest "$target_image"
docker push "$target_image"

echo "Published issuer image: $target_image"
