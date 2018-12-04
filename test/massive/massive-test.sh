#!/usr/bin/env bash

BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs readlink -f)"
NOW="$(date '+%Y-%m-%d@%H:%M')"
export RESULTS_DIR="$BASE_DIR/results/$NOW"
export ROS_VERSION='melodic'

# Results for this run of the analysis
mkdir -p "$RESULTS_DIR"

# Updating rosdistro and logging hash
git submodule update
git submodule status | grep rosdistro | xargs \
    | awk '{print substr($1, 1, 7)}' \
    | xargs -i echo "Rosdistro hash: {}" >> "$RESULTS_DIR/main.log"


export HAROS_HASH="$(git rev-parse HEAD | cut -c 1-7)"

cd ../docker

# Check for cache
docker-compose build haros
# Push newly built image

cd - &> /dev/null

pipenv install
DISTRIBUTION_FILE="$BASE_DIR/rosdistro/$ROS_VERSION/distribution.yaml"
pipenv run python rosdistro.py "$DISTRIBUTION_FILE" --names --urls \
    | grep mavros | while read PACKAGE URL; do
        cd ../docker

        git clone --depth 1 "$URL" "$PACKAGE"

        export PACKAGE
        export PACKAGE_HASH="$(git -C "$PACKAGE" rev-parse HEAD | cut -c 1-7)"

        rm -rf "$PACKAGE"

        # Check for cache
        docker-compose build package
        # Push newly built image

        docker-compose build package-test
        docker-compose run package-test bash
      done


cd - &> /dev/null
