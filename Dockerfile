FROM ros:humble-ros-base-jammy

SHELL ["/bin/bash", "-c"]
ENV DEBIAN_FRONTEND=noninteractive
ENV ARENA_ROOT=/opt/ArenaSDK_Linux_x64

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git python3-colcon-common-extensions python3-rosdep \
    libibverbs-dev librdmacm-dev \
    ros-humble-image-tools ros-humble-image-proc ros-humble-camera-info-manager ros-humble-rqt-reconfigure \
    ros-humble-rviz2 ros-humble-rmw-cyclonedds-cpp \
    && rm -rf /var/lib/apt/lists/*

# Place the vendor archive in vendor/ before building. The archive is not
# redistributed here because LUCID requires authentication to download it.
COPY vendor/ArenaSDK*.tar.gz /tmp/
RUN mkdir -p /opt && tar -xzf /tmp/ArenaSDK*.tar.gz -C /opt \
    && SDK_DIR=$(find /opt -maxdepth 1 -type d -name 'ArenaSDK*' | head -1) \
    && if [ "$SDK_DIR" != "$ARENA_ROOT" ]; then mv "$SDK_DIR" "$ARENA_ROOT"; fi \
    && if [ -f "$ARENA_ROOT/Arena_SDK.conf" ]; then sh "$ARENA_ROOT/Arena_SDK.conf"; fi \
    && printf '%s\n' "$ARENA_ROOT/lib64" "$ARENA_ROOT/GenICam/library/lib/Linux64_x64" "$ARENA_ROOT/Metavision/lib" > /etc/ld.so.conf.d/Arena_SDK.conf \
    && ldconfig \
    && rm -f /tmp/ArenaSDK*.tar.gz

WORKDIR /ros2_ws
RUN git clone --depth 1 --branch v1.3 https://github.com/lucidvisionlabs/arena_camera_ros2.git /tmp/arena_camera_ros2 \
    && cp -a /tmp/arena_camera_ros2/ros2_ws/src/. src/ \
    && sed -i 's/, True)/, true)/g' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i 's/image_msg.header.frame_id = std::to_string(pImage->GetFrameId());/image_msg.header.frame_id = topic_.find("triton") != std::string::npos ? "lucid_triton_color_optical_frame" : "lucid_helios_depth_optical_frame";/' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i 's/Arena::ExecuteNode(nodemap, "UserSetLoad");/\/\/ Keep the camera startup User Set selected by the device; do not reload factory Default./' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i '/set_nodes_exposure_();/a\  try { auto nodemap = m_pDevice->GetNodeMap(); Arena::SetNodeValue<bool>(nodemap, "AcquisitionFrameRateEnable", true); Arena::SetNodeValue<double>(nodemap, "AcquisitionFrameRate", 30.0); log_info("Acquisition frame rate limited to 30 FPS"); } catch (...) { log_warn("Could not write acquisition frame rate; using the camera-saved rate"); }' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i '/m_pDevice->StartStream();/i\  try {\n    auto nodemap = m_pDevice->GetNodeMap();\n    Arena::SetNodeValue<int64_t>(nodemap, "GevSCPSPacketSize", 1500);\n  } catch (const std::exception& e) {\n    log_warn(std::string("Could not set GevSCPSPacketSize: ") + e.what());\n  }' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && rm -rf /tmp/arena_camera_ros2
RUN source /opt/ros/humble/setup.bash && \
    rosdep install --from-paths src --ignore-src --rosdistro humble -r -y && \
    colcon build --symlink-install

COPY docker/entrypoint.sh /entrypoint.sh
COPY rviz.sh /rviz.sh
COPY docker/start_cameras.sh /start_cameras.sh
COPY docker/publish_calibration.py /publish_calibration.py
RUN chmod +x /entrypoint.sh
RUN chmod +x /rviz.sh
RUN chmod +x /start_cameras.sh
RUN chmod +x /publish_calibration.py
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/start_cameras.sh"]
