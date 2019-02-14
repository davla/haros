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
        if docker-compose build "$SERVICE"; then
            docker-compose push "$SERVICE"
        else
            false
        fi
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

    git -C "$TMP_DIR" checkout "$TAG" > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while checkout out $URL - $TAG; exit 1; }

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

    yes | docker container prune

    docker image ls | grep -P "$PATTERN" | grep -v 'haros-deps' \
        | awk '{print $1 ":" $2}' | xargs docker image rm

    docker image ls | grep '<none>' | awk '{print $3}' | xargs docker image rm
}

#####################################################
#
#                   Variables
#
#####################################################

BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs -i readlink -f '{}/..')"
GET_HASHES=true
NOW="$(date '+%Y-%m-%d@%H:%M')"
PACKAGE_DEVEL=false
ROS_DISTRO='melodic'

DOCKER_DIR="$BASE_DIR/../docker"
RESULTS_DIR="$BASE_DIR/results/$NOW"

MAIN_LOG="$RESULTS_DIR/main.log"

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

while getopts 'b:df:Hh:r:p:' OPTION; do
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

        'H')
            GET_HASHES=false
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

[[ -z "$HAROS_HASH"  ]] && {
    echo >&2 'No haros hash specified (-h)'
    exit 1
}

[[ -z "$BONSAI_HASH"  ]] && {
    echo >&2 'No bonsai hash specified (-b)'
    exit 1
}

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
            $GET_HASHES \
                && PACKAGE_HASH="$(get_hash "$VCS" "$URL" "$TAG")" \
                || PACKAGE_HASH="$TAG"

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
        if build-if-not-in-hub 'package-build'; then
            build-if-not-in-hub 'analysis'

            # Analysing
            docker-compose up analysis
            docker-compose down
        else
            echo "$PACKAGE_ID: build failed" >> "$MAIN_LOG"
        fi

        # Saving disk space
        rm-images "$PACKAGE_ID"

        # Cleaning up variables
        unset ANALYSIS_IMAGE BUILD_IMAGE PACKAGE_ID
        unset PACKAGE PACKAGE_NAME PACKAGE_HASH PACKAGE_URL
    done

# Saving disk space
rm-images '(bonsai|haros)'

cd - &> /dev/null || exit 1
