#!/usr/bin/env bash

###############################################################################
#                                                                             #
#                            Input processing                                 #
#                                                                             #
###############################################################################

INPUT_FILE="$HOME/results/${PACKAGE/\//--}.json"
OUTPUT_FILE="$HOME/results/${PACKAGE/\//--}-faulted.json"

###############################################################################
#                                                                             #
#                              Data getters                                   #
#                                                                             #
###############################################################################

function names_in_calls {
    local RULE_NAME="$1"
    local JSON_FILE="$2"

    jq -r ".queries[]
        | select(.rule == \"user:$RULE_NAME\")
        | .comment[15:-1]
        | gsub(\",\"; \"\") | gsub(\":\"; \" \")
        | split(\" \")
        | select(.[-2] != \"?\")
        | [.[1], .[2], .[-2], .[-1]] | join(\" \")" "$JSON_FILE"
}

function unmatched_name {
    local RULE_NAME="$1"
    local JSON_FILE="$2"

    jq -r ".queries[]
        | select(.rule == \"user:$RULE_NAME\")
        | .comment[13:]" "$JSON_FILE"
}

###############################################################################
#                                                                             #
#                             Misc functions                                  #
#                                                                             #
###############################################################################

function find_file {
    local FILE="$1"

    FILE_PATH="$HOME/catkin_ws/src/$PACKAGE/$FILE"
    [[ -f "$FILE_PATH" ]] || {
        FILE_PATH="$HOME/catkin_ws/src/$FILE"
        [[ -f "$FILE_PATH" ]] \
            || FILE_PATH="$(find "$HOME/catkin_ws/src/" -path "*/$FILE")"
    }

    echo "$FILE_PATH"
}

function find_undetected {
    local INJECTION_NAME="$1"
    local MATCH_RULE="$2"
    local JSON_IN="$3"
    local JSON_OUT="$4"

    local TMP
    TMP=$(mktemp)
    jq -r ".fault_injection.$INJECTION_NAME.names[]" "$JSON_OUT" \
        | sort -u > "$TMP"
    UNDETECTED="$(diff --changed-group-format='%<' \
            --unchanged-group-format='' \
        "$TMP" \
        <(unmatched_name "$MATCH_RULE" "$JSON_IN" \
            | grep -f "$TMP" | sort -u) | xargs)"
    rm "$TMP"

    mv "$JSON_OUT" "$JSON_OUT.old"
    jq ".fault_injection.$INJECTION_NAME.undetected |=
        [$(concat $UNDETECTED)]" "$JSON_OUT.old" > "$JSON_OUT"
    rm "$JSON_OUT.old"
}

function edited_file {
    local FILE="$1"
    local FILE_NAME="$(basename "$FILE")"
    local DIR_NAME="$(dirname "$FILE")"

    git -C "$DIR_NAME" status -s | grep -q "$FILE_NAME"
}

function concat {
    [[ $# -eq 0 ]] && {
        echo -n ''
        return
    }

    echo -n "\"$1\""
    for ITEM in "${@:2}"; do
        echo -n ", \"$ITEM\""
    done
}

###############################################################################
#                                                                             #
#                            Fault injections                                 #
#                                                                             #
###############################################################################

declare -A INJECTIONS
INJECTIONS[wrong_publisher]='advertise_info match_topics'
INJECTIONS[wrong_subscriber]='subscribe_info match_topics'
INJECTIONS[wrong_service]='service_info match_services'
INJECTIONS[wrong_client]='client_info match_services'

function change_name {
    local FILE="$1"
    local LINE="$2"
    local NAME="$3"

    sed -n "${LINE}p" "$FILE" | grep -q "$NAME" \
        && sed -i "${LINE}s/$NAME/${NAME:1}/g" "$FILE" \
        || sed -i "s/$NAME/${NAME:1}/g" "$FILE"
}

function change_ns {
    true
}

function remove_node {
    true
}

###############################################################################
#                                                                             #
#                              Doing things                                   #
#                                                                             #
###############################################################################

bash analysis.sh "$INPUT_FILE"
jq -n '{"fault_injection": {}}' > "$OUTPUT_FILE"

for INJECTION_NAME in "${!INJECTIONS[@]}"; do
    read RULE MATCH_RULE < <(echo "${INJECTIONS[$INJECTION_NAME]}")

    THIS_OUT="${OUTPUT_FILE%.json}.$INJECTION_NAME.json"
    NAMES=()
    FILES_NOT_FOUND=()

    while read FILE LINE NAME FULL_NAME; do
        FILE_PATH="$(find_file "$FILE")"
        [[ -z "$FILE_PATH" ]] && {
            FILES_NOT_FOUND+=("$FILE_PATH")
            continue
        }

        NAMES+=("$FULL_NAME")

        edited_file "$FILE_PATH" && continue

        change_name "$FILE_PATH" "$LINE" "$NAME"
    done < <(names_in_calls "$RULE" "$INPUT_FILE")

    bash analysis.sh "$THIS_OUT"

    for DIR in $(find /home/ros/catkin_ws/src/ -maxdepth 3 -type d \
            -name '.git'); do
        dirname "$DIR" | xargs -i git -C '{}' checkout -- '{}'
    done

    mv "$OUTPUT_FILE" "$OUTPUT_FILE.old"
    jq ".fault_injection.$INJECTION_NAME |= {\
        \"names\": [$(concat "${NAMES[@]}")],\
        \"files_not_found\": [$(concat "${FILES_NOT_FOUND[@]}")]\
    }" "$OUTPUT_FILE.old" > "$OUTPUT_FILE"
    rm "$OUTPUT_FILE.old"

    find_undetected "$INJECTION_NAME" "$MATCH_RULE" "$THIS_OUT" "$OUTPUT_FILE"
done
