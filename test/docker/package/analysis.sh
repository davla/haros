#!/usr/bin/env bash

source /home/ros/catkin_ws/devel/setup.bash

RESULTS_FILE="$HOME/results/${PACKAGE/\//--}.json"

cd "$HOME/haros" || exit 1

python -m haros --debug analyse -n
python -m haros --debug export -p massive-analysis "$HOME/.haros/export"

if cd "$HOME/.haros/export/massive-analysis/compliance" &> /dev/null; then
    jq -n "{
        package: \"$PACKAGE\",
        hash: \"$PACKAGE_HASH\",
        queries: [inputs[] | select(.comment
                | type == \"string\" and startswith(\"Query\"))]
    }" runtime/*.json source/*.json > "$RESULTS_FILE"
else
    jq -n "{
        package: \"$PACKAGE\",
        hash: \"$PACKAGE_HASH\",
        queries: []
    }" > "$RESULTS_FILE"
fi
