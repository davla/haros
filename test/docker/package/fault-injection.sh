#!/usr/bin/env bash

INPUT_FILE="$HOME/results/${PACKAGE/\//--}.json"
OUTPUT_FILE="$HOME/results/${PACKAGE/\//--}-faulted.json"

bash analysis.sh "$INPUT_FILE"

jq -r ".queries[]
    | select(.rule | endswith(\"info\"))
    | .comment[15:-1]
    | gsub(\",\"; \"\") | gsub(\":\"; \" \")
    | split(\" \")
    | select(.[-1] != \"?\")
    | [.[1], .[2], .[-1]] | join(\" \")" "$INPUT_FILE" \
    | while read FILE LINE NAME; do
        FILE="$HOME/catkin_ws/src/$PACKAGE/$FILE"
        [[ -f "$FILE" ]] || {
            FILE="$HOME/catkin_ws/src/$FILE"
            [[ -f "$FILE" ]] \
                || FILE="$(find "$HOME/catkin_ws/src/" -path "*/$FILE")"
        }

        sed -i "${LINE}s/$NAME/${NAME:1}/" "$FILE"
    done

bash analysis.sh "$OUTPUT_FILE"
