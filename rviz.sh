#!/usr/bin/env bash
set -e

if [ -f /opt/ros/humble/setup.bash ]; then
  source /opt/ros/humble/setup.bash
else
  echo "ROS 2 Humble setup file not found: /opt/ros/humble/setup.bash" >&2
  exit 1
fi

HOST_WS="/home/iwtros/Documents/ar/thesis/host_ros_ws"
if [ -f "$HOST_WS/install/setup.bash" ]; then
  source "$HOST_WS/install/setup.bash"
fi

# Match the camera container's ROS 2 middleware settings.
export ROS_DOMAIN_ID=0
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp

# Use the current desktop display; fall back to an available local X11 socket
# when this script is launched from a shell with a stale DISPLAY value.
display_number="${DISPLAY#:}"
if [ -z "${DISPLAY:-}" ] || [ ! -S "/tmp/.X11-unix/X${display_number%%.*}" ]; then
  for socket in /tmp/.X11-unix/X*; do
    if [ -S "$socket" ]; then
      export DISPLAY=":${socket##*X}"
      break
    fi
  done
fi
if [ -z "${DISPLAY:-}" ]; then
  echo "No local graphical display detected" >&2
  exit 1
fi

RVIZ_CONFIG="/home/iwtros/Documents/ar/thesis/config/lucid_cameras.rviz"
test -f "$RVIZ_CONFIG" || { echo "RViz config not found: $RVIZ_CONFIG" >&2; exit 1; }

exec rviz2 -d "$RVIZ_CONFIG"
