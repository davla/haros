ARG HAROS_HASH
ARG ROS_VERSION

FROM ros:$ROS_VERSION-ros-base AS init

ARG ROS_VERSION

# Installing dependencies
RUN apt-get update && apt-get install -y python3-pip
RUN pip3 install rosinstall_generator

# Adding user ros, so as not to execute the container as root
RUN useradd -m -U -s /bin/bash ros

# Create catkin workspace
RUN mkdir -p /home/ros/catkin_ws/src
WORKDIR /home/ros/catkin_ws
RUN bash -c "source /opt/ros/$ROS_VERSION/setup.bash && catkin_make"

FROM init AS package

ARG PACKAGE
ARG ROS_VERSION

# Installing the package and its dependencies
RUN rosinstall_generator --deps --rosdistro="$ROS_VERSION" "$PACKAGE" \
    > pkgs.rosinstall
RUN rosws init src pkgs.rosinstall

# Installing system dependencies
RUN bash -c "source /opt/ros/$ROS_VERSION/setup.bash \
    && apt-get update && rosdep init; rosdep update \
    && rosdep install --from-paths src -i --rosdistro=$ROS_VERISION -y \
    && apt-get clean && rm -rf /var/lib/apt/lists/*"

# Building the package
RUN bash -c "source /opt/ros/$ROS_DISTRO/setup.bash \
    && catkin_make_isolated --install --install-space /opt/ros/$ROS_DISTRO \
        --merge -DCMAKE_EXPORT_COMPILE_COMMANDS=1 -DCMAKE_BUILD_TYPE=Release"

# Changing ownership of catkin workspace, so that it can be used as user ros
RUN chown -R ros:ros /home/ros/catkin_ws
USER ros

# Copying the built catkin workspace in the haros image
FROM davla/thesis:haros-$HAROS_HASH AS haros

ARG PACKAGE

COPY --from=package --chown=ros:ros /home/ros/catkin_ws /home/ros/catkin_ws

# Setting Haros up haros
WORKDIR /home/ros/haros
RUN bash -c "export PYTHONPATH=\"/home/ros/haros/bonsai:$PYTHONPATH\" \
    && source /opt/ros/$ROS_DISTRO/setup.bash \
    && source /home/ros/catkin_ws/devel/setup.bash \
    && python -m haros init"
COPY --chown=ros:ros ./configs.yaml /home/ros/.haros/configs.yaml
COPY --chown=ros:ros ./project.yaml /home/ros/.haros/index.yaml

# Dynamic generation of package configuration: all launch files are added
RUN echo "\n\
packages:\n\
  - $PACKAGE\n\
\n\
configurations:\n\
  massive-analysis:" >> /home/ros/.haros/index.yaml
RUN find "/home/ros/catkin_ws/src/$PACKAGE" -name '*.launch' \
    -printf "    - %P\n" >> /home/ros/.haros/index.yaml

# Running the analysis
COPY --chown=ros:ros ./analysis.sh ./analysis.sh
CMD ["bash", "analysis.sh"]
