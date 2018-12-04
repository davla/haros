# Docker image with Haros installed

###############################################################################
#                                                                             #
#                     Haros dependencies installation                         #
#                                                                             #
###############################################################################

ARG ROS_VERSION

FROM ros:$ROS_VERSION-ros-base as deps

# Adding user ros, so as not to execute the container as root
RUN useradd -m -U -s /bin/bash ros

# Installing packages
COPY ./artful.list /etc/apt/sources.list.d/
RUN apt-get update \
    && apt-get -y install git libclang-3.8-dev python-clang-3.8 python-pip

# Installing utility packages
RUN apt-get update && apt-get -y install jq less nano tree

# Installing haros dependencies
RUN pip install -e \
    git+https://github.com/timtadh/pyflwor.git#egg=pyflwor
RUN pip install -e \
    git+https://github.com/davla/bonsai.git@feature/py-parser#egg=bonsai-code
RUN chown -R ros:ros /src

###############################################################################
#                                                                             #
#                          Haros initialization                               #
#                                                                             #
###############################################################################

FROM deps as haros

ARG HAROS_HASH

USER ros
WORKDIR /home/ros

# Cloning haros and bonsai
RUN git clone -b master 'https://github.com/davla/haros.git' haros \
    && git -C haros reset --hard "$HAROS_HASH"
