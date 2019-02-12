#!/usr/bin/env bash

# shellcheck disable=2139

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

get_git() {
    local URL="$1" TAG="$2"

    local TMP_DIR
    TMP_DIR="$(mktemp -d)"
    [ -z $TMP_DIR ] && { echo >&2 Could not create temporary directory - $URL - $TAG; exit 1; }

    git clone "$URL" "$TMP_DIR" &> /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while cloning $URL - $TAG; exit 1; }

    git -C "$TMP_DIR" fetch --tags > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while fetching tags $URL - $TAG; exit 1; }

    git -C "$TMP_DIR" reset --hard "$TAG" > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while resetting $URL - $TAG; exit 1; }

    git -C "$TMP_DIR" rev-parse --short "$TAG"
    [ $? -ne 0 ] && { echo >&2 Error while printing hash for $URL - $TAG; exit 1; }

    rm -rf "$TMP_DIR"
}

get_hg() {
    local URL="$1" TAG="$2"

    local TMP_DIR
    TMP_DIR="$(mktemp -d)"
    [ -z $TMP_DIR ] && { echo >&2 Could not create temporary directory - $URL - $TAG; exit 1; }

    hg clone "$URL" "$TMP_DIR" &> /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while cloning $URL - $TAG; exit 1; }

    hg --cwd "$TMP_DIR" pull > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while pulling $URL - $TAG; exit 1; }

    hg --cwd "$TMP_DIR" update "$TAG" > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while updating $URL - $TAG; exit 1; }

    hg --cwd "$TMP_DIR" id -i
    [ $? -ne 0 ] && { echo >&2 Error while printing hash for $URL - $TAG; exit 1; }

    rm -rf "$TMP_DIR"
}

get_hash() {
    case "$1" in
        'git')
            get_git "${@:2}"
            ;;

        'hg')
            get_hg "${@:2}"
            ;;

        *)
            echo >&2 "$1: vcs unknown (${*:2})"
            ;;
    esac
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

BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs -i readlink -f '{}/..')"
NOW="$(date '+%Y-%m-%d@%H:%M')"
HAROS_HASH="$(git rev-parse --short HEAD)"
PACKAGE_DEVEL=false
ROS_DISTRO='melodic'

BONSAI_HOME="$BASE_DIR/../../../bonsai"
DOCKER_DIR="$BASE_DIR/../docker"
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
# shellcheck disable=2139
alias get-packages="pipenv run python \"$BASE_DIR/py/ros-packages.py\"\
\"\$ROS_DISTRO\" --names --urls"

while getopts 'b:df:h:r:p:' OPTION; do
    case "$OPTION" in
        'b')
            BONSAI_HASH="$OPTARG"
            ;;

        'd')
            PACKAGE_DEVEL=true
            alias get-packages="pipenv run python \
\"$BASE_DIR/py/ros-packages.py\" \"\$ROS_DISTRO\" --names --urls --devel"
            ;;

        'f')
            # shellcheck disable=2139
            alias select-packages="grep -P -f '$OPTARG'"
            ;;

        'h')
            HAROS_HASH="$OPTARG"
            ;;

        'p')
            # shellcheck disable=2139
            [[ -e "$OPTARG" ]] \
                && alias get-packages="cat $OPTARG" \
                || alias get-packages="echo $OPTARG"
            ;;

        'r')
            # shellcheck disable=2139
            alias select-packages="shuf -n ${OPTARG:-20}"
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

export BONSAI_HASH HAROS_HASH PACKAGE_DEVEL RESULTS_DIR ROS_DISTRO

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

cd "$DOCKER_DIR" || exit 1

# Logging in on docker registry
[[ -f "$BASE_DIR/docker-password.txt" ]] \
    && < "$BASE_DIR/docker-password.txt" docker login -u davla --passowrd-stdin \
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
get-packages | select-packages | while read PACKAGE URL TAG VCS; do
        cd "$DOCKER_DIR" || exit 1

        if [[ -n "$URL" && -n "$TAG" && -n "$VCS" ]]; then

            # Getting package hash for docker-compose
            PACKAGE_HASH="$(get_hash "$VCS" "$URL" "$TAG")"
            PACKAGE_ID="${PACKAGE/\//--}-$PACKAGE_HASH"
        else
            PACKAGE_ID="$PACKAGE"

            PACKAGE="${PACKAGE//--/\/}"
            PACKAGE="${PACKAGE%-*}"
            PACKAGE="${PACKAGE##*-}"

            PACKAGE_HASH="${PACKAGE_ID##*-}"
        fi

        PACKAGE_NAME="$(basename "$PACKAGE")"
        BUILD_IMAGE="$PACKAGE_ID"
        ANALYSIS_IMAGE="haros-$HAROS_HASH-bonsai-$BONSAI_HASH-$PACKAGE_ID"

        export ANALYSIS_IMAGE BUILD_IMAGE PACKAGE_ID
        export PACKAGE PACKAGE_NAME PACKAGE_HASH PACKAGE_URL="$URL"

        # Building the analysis images
        build-if-not-in-hub 'package-build'
        build-if-not-in-hub 'analysis'

        # Analysing
        docker-compose up analysis
        docker-compose down

        # Saving disk space
        rm-images "$PACKAGE_ID"

        # Cleaning up variables
        unset ANALYSIS_IMAGE BUILD_IMAGE PACKAGE_ID
        unset PACKAGE PACKAGE_NAME PACKAGE_HASH PACKAGE_URL
    done

# Saving disk space
rm-images '(bonsai|haros)'

cd - &> /dev/null || exit 1
