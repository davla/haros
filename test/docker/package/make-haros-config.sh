#!/usr/bin/env bash

source /opt/ros/$ROS_DISTRO/setup.bash
source /home/ros/catkin_ws/devel/setup.bash

HAROS_PROJECT_FILE='/home/ros/.haros/index.yaml'

declare -A PACKAGE_DIRS
PACKAGE_DIRS["$PACKAGE_NAME"]=$(rospack find "$PACKAGE_NAME")
[[ $? -ne 0 ]] && {
    unset PACKAGE_DIRS["$PACKAGE_NAME"]
    while read NAME DIR; do
        PACKAGE_DIRS["$NAME"]="$DIR"
    done < <(rospack list | grep "$PACKAGE_NAME")
}

echo 'packages:' >> "$HAROS_PROJECT_FILE"

for NAME in "${!PACKAGE_DIRS[@]}"; do
    echo "  - ${NAME}" >> "$HAROS_PROJECT_FILE"
done

echo 'configurations:' >> "$HAROS_PROJECT_FILE"

for NAME in "${!PACKAGE_DIRS[@]}"; do
    DIR="${PACKAGE_DIRS[$NAME]}"

    echo "  ${NAME}:" >> "$HAROS_PROJECT_FILE"

    LAUNCH="$(find "$DIR" -name '*.launch' -printf "    - $NAME/%P\n")"
    if [[ -n "$LAUNCH" ]]; then
        echo -e "$LAUNCH" >> "$HAROS_PROJECT_FILE"
    else
        echo '    []' >> "$HAROS_PROJECT_FILE"
    fi
done
