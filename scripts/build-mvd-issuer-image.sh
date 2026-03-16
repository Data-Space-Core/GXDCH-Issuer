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

if ! command -v java >/dev/null 2>&1; then
  echo "Java is not installed. Install OpenJDK 17 JDK before building." >&2
  exit 1
fi

if ! command -v javac >/dev/null 2>&1; then
  echo "Java compiler not found. You have a JRE but not a JDK." >&2
  echo "Install OpenJDK 17 JDK, for example:" >&2
  echo "  sudo apt-get update && sudo apt-get install -y openjdk-17-jdk" >&2
  exit 1
fi

java_version="$(java -version 2>&1 | head -n 1 || true)"
if [[ "$java_version" != *"17."* ]]; then
  echo "Java 17 is required. Current version:" >&2
  echo "  $java_version" >&2
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
