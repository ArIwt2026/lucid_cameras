#!/usr/bin/env bash
set -e

source /opt/ros/humble/setup.bash
source /ros2_ws/install/setup.bash

export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}"
export RMW_IMPLEMENTATION="${RMW_IMPLEMENTATION:-rmw_cyclonedds_cpp}"

ros2 run arena_camera_node start --ros-args \
  -r __node:=triton_camera \
  -p 'serial:="240601768"' \
  -p topic:=/lucid/triton/image_raw \
  -p pixelformat:=bayer_rggb8 \
  -p binning:=2 \
  -p gain:=0.0 \
  -p gamma:=0.01 \
  -p qos_reliability:=best_effort &
triton_pid=$!

sleep 2

ros2 run arena_camera_node start --ros-args \
  -r __node:=helios_camera \
  -p 'serial:="240901256"' \
  -p topic:=/lucid/helios/image_raw \
  -p pixelformat:=mono16 \
  -p scan3d_operating_mode:=Distance1250mmSingleFreq \
  -p exposure_time_selector:=Exp250Us \
  -p scan3d_distance_min:=0 \
  -p scan3d_spatial_filter:=true \
  -p scan3d_confidence_threshold_min:=150 \
  -p qos_reliability:=best_effort &
helios_pid=$!

# Convert Triton's raw Bayer stream to a standard color image in ROS.
# The default bilinear debayering is the lowest-latency real-time option.
ros2 run image_proc debayer_node --ros-args \
  -p debayer:=0 \
  -r image_raw:=/lucid/triton/image_raw \
  -r image_color:=/lucid/triton/image_color &
debayer_pid=$!

python3 /publish_calibration.py &
calibration_pid=$!

trap 'kill "$triton_pid" "$helios_pid" "$debayer_pid" "$calibration_pid" 2>/dev/null || true' EXIT INT TERM
# Keep the Triton stream and calibration publisher alive even if the optional
# Helios node exits because its current camera profile rejects a setting.
wait "$triton_pid" "$debayer_pid" "$calibration_pid"
exit $?
