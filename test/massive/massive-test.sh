#!/usr/bin/env bash

#####################################################
#
#                   Functions
#
#####################################################

function build-if-not-in-hub {
    local SERVICE="$1"
    local FORCE_BUILD="${2:-false}"

    if [[ "$FORCE_BUILD" == 'true' ]] || ! docker-compose pull "$SERVICE"; then
        docker-compose build "$SERVICE"
        docker-compose push "$SERVICE"
    fi
}

function latest-hash {
    local GIT_REPO="$1"
    local BRANCH="$2"
    local TAG="${3:-HEAD}"

    local TMP_DIR
    TMP_DIR="$(mktemp -d)"
    [[ -z "$BRANCH" ]] \
        && git clone --depth 1 "$GIT_REPO" "$TMP_DIR" &> /dev/null \
        || git clone -b "$BRANCH" --depth 1 "$GIT_REPO" "$TMP_DIR" &> /dev/null
    git -C "$TMP_DIR" fetch --tags &> /dev/null

    local LATEST_HASH
    LATEST_HASH="$(git -C "$TMP_DIR" rev-parse --short "$TAG")"

    rm -rf "$TMP_DIR" &> /dev/null

    echo "$LATEST_HASH"
}

function rm-images {
    local PATTERN="$1"

    docker image ls | grep -P "$PATTERN" | grep -v 'haros-deps' \
        | awk '{print $1 ":" $2}' | xargs docker image rm
}

#####################################################
#
#                   Variables
#
#####################################################

BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs readlink -f)"
NOW="$(date '+%Y-%m-%d@%H:%M')"
HAROS_HASH="$(git rev-parse --short HEAD)"
ROS_DISTRO='melodic'

BONSAI_HOME="$BASE_DIR/../../../bonsai"
RESULTS_DIR="$BASE_DIR/results/$NOW"

MAIN_LOG="$RESULTS_DIR/main.log"

[[ -d "$BONSAI_HOME" ]] \
    && BONSAI_HASH="$(git -C "$BONSAI_HOME" rev-parse --short HEAD)" \
    || BONSAI_HASH="$(latest-hash 'https://github.com/davla/bonsai.git' \
        'py-parser')"

#####################################################
#
#               Input processing
#
#####################################################

shopt -s expand_aliases

alias select-packages='cat'

while getopts 'h:b:R' OPTION; do
    case "$OPTION" in
        'b')
            BONSAI_HASH="$OPTARG"
            ;;

        'h')
            HAROS_HASH="$OPTARG"
            ;;

        'R')
            alias select-packages='shuf -n 20'
            ;;

        *)
            exit 1
            ;;
    esac
done

#####################################################
#
#       Exporting variables to environment
#
#####################################################

export BONSAI_HASH HAROS_HASH RESULTS_DIR ROS_DISTRO

#####################################################
#
#               Initial setup
#
#####################################################

# Results for this run of the analysis
mkdir -p "$RESULTS_DIR"
chmod -R o+w "$RESULTS_DIR"

# Updating rosdistro and logging hash
git submodule update
git submodule status | grep rosdistro | xargs \
    | awk '{print substr($1, 1, 7)}' \
    | xargs -i echo "Rosdistro hash: {}" >> "$MAIN_LOG"

# Logging bonsai and haros hashes
echo "Bonsai hash: $BONSAI_HASH" >> "$MAIN_LOG"
echo "Haros hash: $HAROS_HASH" >> "$MAIN_LOG"

# Setting python scripts environment
pipenv install

#####################################################
#
#           Docker initial setup
#
#####################################################

cd ../docker || exit 1

# Logging in on docker registry
[[ -f ./docker-password.txt ]] \
    && < ./docker-password.txt docker login -u davla --passowrd-stdin \
    || docker login

# Building base and dependencies - likely done once and for all
build-if-not-in-hub 'base'
build-if-not-in-hub 'haros-deps'

# Building bonsai and haros - depends on hash
build-if-not-in-hub 'bonsai'
build-if-not-in-hub 'haros'

cd - &> /dev/null || exit 1

#####################################################
#
#               Scanning packages
#
#####################################################

# Getting all package names and urls
pipenv run python ros-packages.py "$ROS_DISTRO" --names --urls \
    | select-packages | while read PACKAGE URL TAG; do
        cd ../docker || exit 1

        # Getting package hash for docker-compose
        PACKAGE_HASH="$(latest-hash "$URL" '' "$TAG")"
        PACKAGE_ID="${PACKAGE/\//--}-$PACKAGE_HASH"
        PACKAGE_NAME="$(basename "$PACKAGE")"

        export PACKAGE PACKAGE_NAME PACKAGE_ID

        # Building the package and the analysis iages
        build-if-not-in-hub 'package-build'
        build-if-not-in-hub 'analysis'

        # Analysinz
        docker-compose up analysis
        docker-compose down

        # Saving disk space
        rm-images "$PACKAGE_ID"
      done

# Saving disk space
rm-images '(bonsai|haros)'

cd - &> /dev/null || exit 1
