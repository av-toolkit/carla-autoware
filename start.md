
# 启动carla仿真
docker run --privileged --gpus all --net=host -e DISPLAY=$DISPLAY -e SDL_VIDEODRIVER=x11 -v /tmp/.X11-unix:/tmp/.X11-unix:rw carlasim/carla:0.9.11 /bin/bash ./CarlaUE4.sh -vulkan

# 启动autoware
./run.sh
roslaunch carla_autoware_agent carla_autoware_agent.launch town:=Town01


roslaunch runtime_manager runtime_manager.launch