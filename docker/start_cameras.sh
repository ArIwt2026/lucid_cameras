#!/usr/bin/env bash
set -e

source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

ros2 run arena_camera_node start --ros-args \
  -p 'serial:="240601768"' \
  -p topic:=/lucid/triton/image_raw \
  -p pixelformat:=bayer_rggb8 \
  -p qos_reliability:=best_effort &
triton_pid=$!

ros2 run arena_camera_node start --ros-args \
  -p 'serial:="240901256"' \
  -p topic:=/lucid/helios/image_raw \
  -p pixelformat:=mono16 \
  -p qos_reliability:=reliable &
helios_pid=$!

# Convert Triton's raw Bayer stream to a standard color image in ROS.
# The default bilinear debayering is the lowest-latency real-time option.
ros2 run image_proc debayer_node --ros-args \
  -p debayer:=0 \
  -r image_raw:=/lucid/triton/image_raw \
  -r image_color:=/lucid/triton/image_color &
debayer_pid=$!

trap 'kill "$triton_pid" "$helios_pid" "$debayer_pid" 2>/dev/null || true' EXIT INT TERM
wait -n "$triton_pid" "$helios_pid" "$debayer_pid"
exit $?
