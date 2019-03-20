#!/usr/bin/env bash

INPUT_FILE="$HOME/results/${PACKAGE/\//--}.json"
OUTPUT_FILE="$HOME/results/${PACKAGE/\//--}-faulted.json"

FAULT_INJECTION='"No topics to rename"'
NAMES=()
NOT_FOUND=()

bash analysis.sh "$INPUT_FILE"

while read FILE LINE NAME FULL_NAME; do
    FILE="$HOME/catkin_ws/src/$PACKAGE/$FILE"
    [[ -f "$FILE" ]] || {
        FILE="$HOME/catkin_ws/src/$FILE"
        [[ -f "$FILE" ]] \
            || FILE="$(find "$HOME/catkin_ws/src/" -path "*/$FILE")"
    }

    [[ -z "$FILE" ]] && {
        NOT_FOUND+=("$FILE")
        continue
    }
    NAMES+=("$FULL_NAME")

    sed -i "${LINE}s/$NAME/${NAME:1}/g" "$FILE"
done < <(jq -r ".queries[]
    | select(.rule | endswith(\"info\"))
    | .comment[15:-1]
    | gsub(\",\"; \"\") | gsub(\":\"; \" \")
    | split(\" \")
    | select(.[-1] != \"?\")
    | [.[1], .[2], .[-2], .[-1]] | join(\" \")" "$INPUT_FILE")

bash analysis.sh "$OUTPUT_FILE"

[[ -n "${NOT_FOUND[*]}" || -n "${NAMES[*]}" ]] && {
    ALL_NAMES="\"${NAMES[0]}\""
    for NAME in "${NAMES[@]:1}"; do
        ALL_NAMES="$ALL_NAMES, \"$NAME\""
    done

    ALL_FILES="\"${NOT_FOUND[0]}\""
    for FILE in "${NOT_FOUND[@]:1}"; do
        ALL_FILES="\"$FILE\", $ALL_FILES"
    done

    FAULT_INJECTION="{\
    \"names\": [$ALL_NAMES],\
    \"not_found\": [$ALL_FILES]\
}"
}

mv "$OUTPUT_FILE" "$OUTPUT_FILE.old"
jq ".fault_injection |= $FAULT_INJECTION" "$OUTPUT_FILE.old" > "$OUTPUT_FILE"
rm "$OUTPUT_FILE.old"

jq -r '.fault_injection.names[]' "$OUTPUT_FILE" | sort -u > mangled-names.txt
UNDETECTED="$(diff --changed-group-format='%<' --unchanged-group-format='' \
    mangled-names.txt <(jq -r '.queries[]
                                   | select(.rule | endswith("match_topics"))
                                   | .comment[13:]' "$OUTPUT_FILE" \
                            | grep -f mangled-names.txt | sort -u))"
rm mangled-names.txt

[[ -n "$UNDETECTED" ]] && {
    ALL_UNDETECTED="\"${UNDETECTED[0]}\""
    for NAME in "${UNDETECTED[@]:1}"; do
        ALL_UNDETECTED="\"$NAME\", $ALL_UNDETECTED"
    done

    mv "$OUTPUT_FILE" "$OUTPUT_FILE.old"
    jq ".fault_injection.undetected |= [$ALL_UNDETECTED]" "$OUTPUT_FILE.old" \
        > "$OUTPUT_FILE"
    rm "$OUTPUT_FILE.old"
}
