#!/usr/bin/env bash

ROS_VERSION='melodic'
BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs readlink -f)"

USER="$1"

# Adding python 3.6 repository
add-apt-repository ppa:deadsnakes/ppa

# Adding docker repository
wget -qO - 'https://download.docker.com/linux/ubuntu/gpg' | apt-key add -
echo "
# Docker Ubuntu CE

deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update

# Installing dependencies
apt-get install docker-ce git jq python python-yaml python3 python3-pip \
    python3.6
pip3 install rosinstall_generator pipenv

#####################################################
#
#                   Functions
#
#####################################################

# This function returns the initial part of the URL of a GitHub repository
# latest release.
#
# Argunemts:
#   - $1: The GitHub repository name
function latest-release-url {
    local RELEASES_URL="https://api.github.com/repos/$1/releases"
    local DOWNLOAD_URL="https://github.com/$1/releases/download"

    local LATEST_RELEASE
    LATEST_RELEASE="$(wget -O - "$RELEASES_URL/latest" | jq -r '.tag_name')"
    echo "$DOWNLOAD_URL/$LATEST_RELEASE"
}

#####################################################
#
#               Docker compose
#
#####################################################

COMPOSE_TAG="$(uname -s)-$(uname -m)"
COMPOSE_URL="$(latest-release-url 'docker/compose')/docker-compose-$COMPOSE_TAG"
wget -O /usr/local/bin/docker-compose "$COMPOSE_URL"
chmod +x /usr/local/bin/docker-compose

# Cloning rosdistro if not there already
runuser -u "$USER" git submodule init
runuser -u "$USER" git submodule update

# Creating pipenv environment for massive testing
runuser -u "$USER" pipenv install
