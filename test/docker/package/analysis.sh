#!/usr/bin/env bash

source /home/ros/catkin_ws/devel/setup.bash
RESULTS_DIR="$HOME/results"

cd "$HOME/haros"

python -m haros --debug analyse -n
python -m haros --debug export -p massive-analysis "$HOME/.haros/export"

cd "$HOME/.haros/export/massive-analysis/compliance"

jq -n "{ \
    package: \"$PACKAGE\", \
    hash: \"$PACKAGE_HASH\", \
    queries: [inputs[] | select(.comment|startswith(\"Query\"))] \
}" runtime/*.json source/*.json > "$RESULTS_DIR/$PACKAGE.json"
