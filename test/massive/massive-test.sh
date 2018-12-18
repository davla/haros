#!/usr/bin/env bash

function rm-images {
    local PATTERN="$1"

    docker image ls | grep -P "$PATTERN" | grep -v 'haros-deps' \
        | awk '{print $1 ":" $2}' | xargs docker image rm
}

function latest-hash {
    local GIT_REPO="$1"
    local BRANCH="${2:-master}"

    local TMP_DIR="$(mktemp -d)"
    git clone -b "$BRANCH" --depth 1 "$GIT_REPO" "$TMP_DIR" &> /dev/null

    local LATEST_HASH="$(git -C "$TMP_DIR" rev-parse HEAD | cut -c 1-7)"

    rm -rf "$TMP_DIR" &> /dev/null

    echo "$LATEST_HASH"
}

function build-if-not-in-hub {
    local SERVICE="$1"
    local FORCE_BUILD="${2:-false}"

    if [[ "$FORCE_BUILD" == 'true' ]] || ! docker-compose pull "$SERVICE"; then
        docker-compose build "$SERVICE"
        docker-compose push "$SERVICE"
    fi
}

BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs readlink -f)"
NOW="$(date '+%Y-%m-%d@%H:%M')"
export RESULTS_DIR="$BASE_DIR/results/$NOW"
export ROS_DISTRO='melodic'

# Results for this run of the analysis
mkdir -p "$RESULTS_DIR"
chmod -R o+w "$RESULTS_DIR"

# Updating rosdistro and logging hash
git submodule update
git submodule status | grep rosdistro | xargs \
    | awk '{print substr($1, 1, 7)}' \
    | xargs -i echo "Rosdistro hash: {}" >> "$RESULTS_DIR/main.log"

[[ -d ../../../bonsai ]] \
    && export BONSAI_HASH="$(git -C ../../../bonsai rev-parse HEAD \
        | cut -c 1-7)" \
    || export BONSAI_HASH="$(latest-hash 'https://github.com/davla/bonsai.git' \
        'py-parser')"
export HAROS_HASH="$(git rev-parse HEAD | cut -c 1-7)"

cd ../docker

# Logging in on docker registry
[[ -f ./docker-password.txt ]] \
    && < ./docker-password.txt docker login -u davla --passowrd-stdin \
    || docker login

build-if-not-in-hub 'base'
build-if-not-in-hub 'haros-deps'

build-if-not-in-hub 'bonsai'
build-if-not-in-hub 'haros'

cd - &> /dev/null

pipenv install
DISTRIBUTION_FILE="$BASE_DIR/rosdistro/$ROS_DISTRO/distribution.yaml"
pipenv run python rosdistro.py "$DISTRIBUTION_FILE" --names --urls \
    | while read PACKAGE URL; do
        cd ../docker

        export PACKAGE
        export PACKAGE_HASH="$(latest-hash "$URL")"

        build-if-not-in-hub 'package-build'
        build-if-not-in-hub 'analysis'

        docker-compose up analysis
        docker-compose down

        rm-images "$PACKAGE"
      done

rm-images '(bonsai|haros)'

cd - &> /dev/null
