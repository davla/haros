#!/usr/bin/env bash

BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs readlink -f)"
NOW="$(date '+%Y-%m-%d@%H:%M')"
export RESULTS_DIR="$BASE_DIR/results/$NOW"
export ROS_DISTRO='melodic'

# Results for this run of the analysis
mkdir -p "$RESULTS_DIR"

# Updating rosdistro and logging hash
git submodule update
git submodule status | grep rosdistro | xargs \
    | awk '{print substr($1, 1, 7)}' \
    | xargs -i echo "Rosdistro hash: {}" >> "$RESULTS_DIR/main.log"

[[ -d /src/bonsai-code ]] \
    && BONSAI_SRC='/src/bonsai-code' \
    || BONSAI_SRC='../../../bonsai'
export BONSAI_HASH="$(git -C "$BONSAI_SRC" rev-parse HEAD | cut -c 1-7)"
export HAROS_HASH="$(git rev-parse HEAD | cut -c 1-7)"

cd ../docker

# Logging in on docker registry
[[ -f ./docker-password.txt ]] \
    && < ./docker-password.txt docker login -u davla --passowrd-stdin \
    || docker login

docker image ls | grep -P '(bonsai|haros)' | grep -v 'haros-deps' \
    | awk '{print $2}' | xargs docker image rm

docker-compose pull base || docker-compose build base
docker-compose push base
docker-compose pull haros-deps || docker-compose build haros-deps
docker-compose push haros-deps

docker-compose pull bonsai || docker-compose build bonsai
docker-compose push bonsai

docker-compose pull haros || docker-compose build haros
docker-compose push haros

cd - &> /dev/null

pipenv install
DISTRIBUTION_FILE="$BASE_DIR/rosdistro/$ROS_DISTRO/distribution.yaml"
pipenv run python rosdistro.py "$DISTRIBUTION_FILE" --names --urls \
    | while read PACKAGE URL; do
        cd ../docker

        git clone --depth 1 "$URL" "$PACKAGE"

        export PACKAGE
        export PACKAGE_HASH="$(git -C "$PACKAGE" rev-parse HEAD | cut -c 1-7)"

        rm -rf "$PACKAGE"

        docker-compose pull package-build || docker-compose build package-build
        docker-compose push package-build
        docker-compose pull analysis || docker-compose build analysis
        docker-compose push analysis

        docker-compose up analysis
        docker-compose down

        docker image ls | grep "$PACKAGE" | awk '{print $2}' \
            | xargs docker image rm
      done

docker image ls | grep -P '(bonsai|haros)' | grep -v 'haros-deps' \
    | awk '{print $2}' | xargs docker image rm

cd - &> /dev/null
