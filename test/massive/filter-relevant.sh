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

    local TMP_DIR
    TMP_DIR="$(mktemp -d)"
    [ -z $TMP_DIR ] && { echo >&2 Could not create temporary directory - $URL - $TAG; exit 1; }

    git clone "$URL" "$TMP_DIR" &> /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while cloning $URL - $TAG; exit 1; }

    git -C "$TMP_DIR" fetch --tags > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while fetching tags $URL - $TAG; exit 1; }

    git -C "$TMP_DIR" reset --hard "$TAG" > /dev/null
    [ $? -ne 0 ] && { echo >&2 Error while resetting $URL - $TAG; exit 1; }

    git -C "$TMP_DIR" rev-parse --short "$TAG" | xargs echo "$TMP_DIR"
    [ $? -ne 0 ] && { echo >&2 Error while printing hash for $URL - $TAG; exit 1; }
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

    local LAUNCH="$(find "$SRC_ROOT" -name '*.launch' -type f | wc -l)"

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
    "launch": $LAUNCH,
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
    [ -z $PACKAGE ] && { echo >&2 PACKAGE is empty - $URL - $TAG; exit 1; }
    [ -z $URL ] && { echo >&2 URL is empty - $PACKAGE - $TAG; exit 1; }
    [ -z $TAG ] && { echo >&2 TAG is empty - $PACKAGE - $URL; exit 1; }

    echo "Cloning $PACKAGE"
    read PACKAGE_ROOT HASH < <(get_package "$URL" "$TAG")

    [ -z $PACKAGE_ROOT ] && { echo >&2 PACKAGE_ROOT is empty - $HASH; exit 1; }
    [ -z $HASH ] && { echo >&2 HASH is empty - $PACKAGE_ROOT; exit 1; }

    echo "Analyzing $PACKAGE"
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
    [ $? -ne 0 ] && exit

    rm -rf "$PACKAGE_ROOT"
	unset PACKAGE_ROOT HASH PACKAGE URL TAG
done

rm transform-filter.jq
