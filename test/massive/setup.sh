#!/usr/bin/env bash

ROS_VERSION='melodic'
BASE_DIR="$(dirname "${BASH_SOURCE[0]}" | xargs feadlink -f)"

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
apt-get install docker-ce git python python-yaml python3 python3-pip python3.6
pip3 install rosinstall_generator pipenv

# Cloning rosdistro if not there already
runuser git submodule init
runuser git submodule update

# Creating pipenv environment for massive testing
runuser pipenv install
