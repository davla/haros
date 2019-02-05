#!/usr/bin/env bash

#####################################################
#
#                   Functions
#
#####################################################

find_tag_by_commit() {
    local COMMIT="$1"
    grep "$COMMIT"
}

get_package() {
    local URL="$1" TAG="$2"

    local TMP_DIR="$(mktemp -d)"
    git clone "$URL" "$TMP_DIR" &> /dev/null
    git -C "$TMP_DIR" fetch --tags > /dev/null
    git -C "$TMP_DIR" reset --hard "$TAG" > /dev/null

    git rev-parse --short HEAD | xargs echo "$TMP_DIR"
}

grep_client_api() {
    local SRC_ROOT="$1"

    local NH=$(grep 'NodeHandle' -R "$SRC_ROOT" | wc -l)
    local NH_ARGS=$(grep -P 'NodeHandle\s+[_a-zA-Z][_a-zA-Z0-9]*\(' \
        -R "$SRC_ROOT" | wc -l)
    local BARE_PUB=$(grep -P 'Publisher\s+[_a-zA-Z][_a-zA-Z0-9]*\(' \
        -R "$SRC_ROOT" | wc -l)
    local PUBLICATION=$(grep 'Publication' -R "$SRC_ROOT" | wc -l)
    local TOPICMANAGER=$(grep 'TopicManager' -R "$SRC_ROOT" | wc -l)
    local LONG_ONE=$(grep 'SingleSubscriberPublisher' -R "$SRC_ROOT" \
        | wc -l)
    local SUBSCRIBER=$(grep 'Subscriber' -R "$SRC_ROOT" | wc -l)
    local PUBLISHER=$(grep 'Publisher' -R "$SRC_ROOT" | wc -l)


    local ADVERTISE="$(grep -P '\.advertise' -R "$SRC_ROOT" | wc -l)"
    local PUBLISH="$(grep -P '\.publish' -R "$SRC_ROOT" | wc -l)"
    local SUBSCRIBE="$(grep -P '\.subscribe' -R "$SRC_ROOT" | wc -l)"

    cat <<SUMMARYEOF
{
    "NodeHandle_base": $NH,
    "NodeHandle_with_arguments": $NH_ARGS,
    "Publisher_bare": $BARE_PUB,
    "Publication": $PUBLICATION,
    "TopicManager": $TOPICMANAGER,
    "SingleSubscriberPublisher": $LONG_ONE,
    "Subscriber": $SUBSCRIBER,
    "Publisher": $PUBLISHER,
    "advertise": $ADVERTISE,
    "publish": $PUBLISH,
    "subscribe": $SUBSCRIBE,
    "total": $(( ADVERTISE + SUBSCRIBE + PUBLISHER + SUBSCRIBER ))
}
SUMMARYEOF
}



#####################################################
#
#               Scanning packages
#
#####################################################

RESULTS_DIR="results/filter"
mkdir -p "$RESULTS_DIR"

while read PACKAGE URL TAG; do
    read PACKAGE_ROOT HASH < <(get_package "$URL" "$TAG")

    cat > transform-filter.jq <<FILTEREOF
{
    "package": {
        "name": "$PACKAGE",
        "url": "$URL",
        "tag": "$TAG",
        "hash": "$HASH"
    }
} * .
FILTEREOF

    grep_client_api "$PACKAGE_ROOT" "$PACKAGE" \
        | jq -f transform-filter.jq > "$RESULTS_DIR/${PACKAGE//\//--}.json"

    rm -rf "$PACKAGE_ROOT"
done

rm transform-filter.jq
