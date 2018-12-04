#!/usr/bin/env bash

source /home/ros/catkin_ws/devel/setup.bash
RESULTS_DIR="$HOME/haros/results"

cd "$HOME/haros"

python -m haros analyse -n
python -m haros export -p massive-analysis "$HOME/.haros/export"

cd "$HOME/.haros/export/massive-analysis/compliance"

jq "{ \
    package: \"$PACKAGE\", \
    hash: \"$PACKAGE_HASH\", \
    queries: inputs[] | select(.comment|startswith(\"Query\")) \
}" runtime/*.json source/*.json > "$RESULTS_DIR/$PACKAGE.json"
