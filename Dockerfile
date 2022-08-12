ARG AUTOWARE_VERSION=latest-melodic-cuda

FROM autoware/autoware:$AUTOWARE_VERSION

USER autoware
ENV USERNAME autoware

WORKDIR /home/autoware

#update keys
USER root
RUN apt-key del 7fa2af80
RUN rm /etc/apt/sources.list.d/cuda.list && rm /etc/apt/sources.list.d/nvidia-ml.list
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-keyring_1.0-1_all.deb
RUN dpkg -i cuda-keyring_1.0-1_all.deb
USER autoware

# Update autoware/simulation package version to latest.
COPY --chown=autoware ./patchs/update_sim_version.patch /home/$USERNAME/Autoware
RUN patch ./Autoware/autoware.ai.repos /home/$USERNAME/Autoware/update_sim_version.patch

# Change code in autoware/simulation package.
COPY --chown=autoware ./patchs/update_sim_code.patch /home/$USERNAME/Autoware/src/autoware/simulation
RUN cd /home/$USERNAME/Autoware \
    && vcs import src < autoware.ai.repos \
    && cd /home/$USERNAME/Autoware/src/autoware/simulation \
    && git apply update_sim_code.patch

# Compile with colcon build.
RUN cd ./Autoware \
    && source /opt/ros/melodic/setup.bash \
    && AUTOWARE_COMPILE_WITH_CUDA=1 colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release

# CARLA PythonAPI
RUN mkdir ./PythonAPI
ADD --chown=autoware https://carla-releases.s3.eu-west-3.amazonaws.com/Backup/carla-0.9.11-py2.7-linux-x86_64.egg ./PythonAPI
RUN echo "export PYTHON2_EGG=$(ls /home/autoware/PythonAPI | grep py2.)" >> .bashrc \
    && echo "export PYTHONPATH=\$PYTHONPATH:~/PythonAPI/\$PYTHON2_EGG" >> .bashrc

# CARLA ROS Bridge
# There is some kind of mismatch between the ROS debian packages installed in the Autoware image and
# the latest ros-melodic-ackermann-msgs and ros-melodic-derived-objects-msgs packages. As a
# workaround we use a snapshot of the ROS apt repository to install an older version of the required
# packages.
USER root
RUN rm -f /etc/apt/sources.list.d/ros1-latest.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-key 4B63CF8FDE49746E98FA01DDAD19BAB3CBF125EA
RUN sh -c 'echo "deb http://snapshots.ros.org/melodic/2020-08-07/ubuntu $(lsb_release -sc) main" >> /etc/apt/sources.list.d/ros-snapshots.list'
RUN apt-get update && apt-get install -y --no-install-recommends \
        python-pip \
        python-wheel \
        ros-melodic-ackermann-msgs \
        ros-melodic-derived-object-msgs \
    && rm -rf /var/lib/apt/lists/*
RUN pip install transforms3d simple-pid pygame networkx==2.2

USER autoware

RUN git clone -b '0.9.11' --recurse-submodules https://github.com/carla-simulator/ros-bridge.git

# Update code in carla-ros-bridge package and fix the tf tree issue.
# The fix has been introduced in latest version (since 0.9.12):
# https://github.com/carla-simulator/ros-bridge/pull/570/commits/9f903cf43c4ef3dd0b909721e044c62a8796f841
COPY --chown=autoware ./patchs/update_ros_bridge.patch /home/$USERNAME/ros-bridge
RUN cd /home/$USERNAME/ros-bridge \
    && git apply update_ros_bridge.patch

# CARLA Autoware agent
COPY --chown=autoware . ./carla-autoware

RUN mkdir -p carla_ws/src
RUN cd carla_ws/src \
    && ln -s ../../ros-bridge \
    && ln -s ../../carla-autoware/carla-autoware-agent \
    && cd .. \
    && source /opt/ros/melodic/setup.bash \
    && catkin_make

RUN echo "export CARLA_AUTOWARE_CONTENTS=~/autoware-contents" >> .bashrc \
    && echo "source ~/carla_ws/devel/setup.bash" >> .bashrc \
    && echo "source ~/Autoware/install/setup.bash" >> .bashrc

# Update Launch Files
RUN mkdir -p ./Documents/patchs
COPY --chown=autoware ./patchs/update_vehicle_model.launch.patch ./Documents/patchs
RUN patch ./Autoware/install/vehicle_description/share/vehicle_description/launch/vehicle_model.launch ./Documents/patchs/update_vehicle_model.launch.patch

# Install Git LFS
USER root
RUN curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
RUN sudo apt-get install git-lfs
RUN git lfs install
USER autoware

# Copy over autoware-contents
RUN git clone -b master https://bitbucket.org/carla-simulator/autoware-contents.git
#RUN mkdir ./autoware-contents
#COPY --chown=autoware $CARLA_AUTOWARE_ROOT/autoware-contents/* /home/$USERNAME/autoware-contents
#ADD --chown=autoware https://bitbucket.org/carla-simulator/autoware-contents.git ./autoware-contents
#ADD $CARLA_AUTOWARE_ROOT/autoware-contents /home/$USERNAME/autoware-contents

USER root

# (Optional) Install vscode
#RUN apt-get update
#RUN apt-get install -y software-properties-common apt-transport-https wget
#RUN wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | apt-key add -
#RUN add-apt-repository "deb [arch=amd64] https://packages.microsoft.com/repos/vscode stable main"
#RUN apt-get -y install code

CMD ["/bin/bash"]
