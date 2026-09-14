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
    && sed -i 's/Arena::SetNodeValue<GenICam::gcstring>(nodemap, "UserSetSelector", "Default");/\/\/ Keep UserSet/' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i 's/Arena::ExecuteNode(nodemap, "UserSetLoad");/\/\/ Keep the camera startup User Set selected by the device; do not reload factory Default./' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i '/set_nodes_exposure_();/a\  try { auto nodemap = m_pDevice->GetNodeMap(); Arena::SetNodeValue<bool>(nodemap, "AcquisitionFrameRateEnable", true); Arena::SetNodeValue<double>(nodemap, "AcquisitionFrameRate", 30.0); log_info("Acquisition frame rate limited to 30 FPS"); } catch (...) { log_warn("Could not write acquisition frame rate; using the camera-saved rate"); }' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i '/m_pDevice->StartStream();/i\  try {\n    auto nodemap = m_pDevice->GetNodeMap();\n    Arena::SetNodeValue<int64_t>(nodemap, "GevSCPSPacketSize", 1500);\n  } catch (...) {\n    log_warn("Could not set GevSCPSPacketSize");\n  }' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i '/bool is_passed_pub_qos_reliability_;/a\  int64_t binning_;\n  double gamma_;\n  std::string scan3d_operating_mode_;\n  std::string exposure_time_selector_;\n  int64_t scan3d_distance_min_;\n  bool scan3d_spatial_filter_;\n  int64_t scan3d_confidence_threshold_min_;' src/arena_camera_node/src/ArenaCameraNode.h \
    && sed -i '/nextParameterToDeclare = "qos_reliability";/i\    nextParameterToDeclare = "binning";\n    binning_ = this->declare_parameter("binning", 1);\n    nextParameterToDeclare = "gamma";\n    gamma_ = this->declare_parameter("gamma", -1.0);\n    nextParameterToDeclare = "scan3d_operating_mode";\n    scan3d_operating_mode_ = this->declare_parameter("scan3d_operating_mode", "");\n    nextParameterToDeclare = "exposure_time_selector";\n    exposure_time_selector_ = this->declare_parameter("exposure_time_selector", "");\n    nextParameterToDeclare = "scan3d_distance_min";\n    scan3d_distance_min_ = this->declare_parameter("scan3d_distance_min", -1);\n    nextParameterToDeclare = "scan3d_spatial_filter";\n    scan3d_spatial_filter_ = this->declare_parameter("scan3d_spatial_filter", false);\n    nextParameterToDeclare = "scan3d_confidence_threshold_min";\n    scan3d_confidence_threshold_min_ = this->declare_parameter("scan3d_confidence_threshold_min", -1);' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i '/set_nodes_load_default_profile_();/a\  if (binning_ > 1) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      try {\n        Arena::SetNodeValue<GenICam::gcstring>(nodemap, "BinningHorizontalMode", "Average");\n        Arena::SetNodeValue<GenICam::gcstring>(nodemap, "BinningVerticalMode", "Average");\n      } catch (...) {}\n      Arena::SetNodeValue<int64_t>(nodemap, "BinningHorizontal", binning_);\n      Arena::SetNodeValue<int64_t>(nodemap, "BinningVertical", binning_);\n      log_info(std::string("Binning set to ") + std::to_string(binning_) + "x" + std::to_string(binning_) + " (Average)");\n    } catch (...) {\n      log_warn("Could not set binning");\n    }\n  }\n  if (gamma_ > 0.0) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      Arena::SetNodeValue<bool>(nodemap, "GammaEnable", true);\n      Arena::SetNodeValue<double>(nodemap, "Gamma", gamma_);\n      log_info(std::string("Set Gamma to ") + std::to_string(gamma_));\n    } catch (...) {\n      log_warn("Could not set Gamma");\n    }\n  }\n  if (!scan3d_operating_mode_.empty()) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      Arena::SetNodeValue<GenICam::gcstring>(nodemap, "Scan3dOperatingMode", scan3d_operating_mode_.c_str());\n      log_info(std::string("Set Scan3dOperatingMode to ") + scan3d_operating_mode_);\n    } catch (...) {\n      log_warn("Could not set Scan3dOperatingMode");\n    }\n  }\n  if (!exposure_time_selector_.empty()) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      Arena::SetNodeValue<GenICam::gcstring>(nodemap, "ExposureTimeSelector", exposure_time_selector_.c_str());\n      log_info(std::string("Set ExposureTimeSelector to ") + exposure_time_selector_);\n    } catch (...) {\n      log_warn("Could not set ExposureTimeSelector");\n    }\n  }\n  if (scan3d_distance_min_ >= 0) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      Arena::SetNodeValue<int64_t>(nodemap, "Scan3dDistanceMin", scan3d_distance_min_);\n      log_info(std::string("Set Scan3dDistanceMin to ") + std::to_string(scan3d_distance_min_) + " mm");\n    } catch (...) {\n      log_warn("Could not set Scan3dDistanceMin");\n    }\n  }\n  if (scan3d_spatial_filter_) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      Arena::SetNodeValue<bool>(nodemap, "Scan3dSpatialFilterEnable", true);\n      log_info("Set Scan3dSpatialFilterEnable to true");\n    } catch (...) {\n      log_warn("Could not set Scan3dSpatialFilterEnable");\n    }\n  }\n  if (scan3d_confidence_threshold_min_ >= 0) {\n    try {\n      auto nodemap = m_pDevice->GetNodeMap();\n      Arena::SetNodeValue<int64_t>(nodemap, "Scan3dConfidenceThresholdMin", scan3d_confidence_threshold_min_);\n      log_info(std::string("Set Scan3dConfidenceThresholdMin to ") + std::to_string(scan3d_confidence_threshold_min_));\n    } catch (...) {\n      log_warn("Could not set Scan3dConfidenceThresholdMin");\n    }\n  }' src/arena_camera_node/src/ArenaCameraNode.cpp \
    && sed -i 's/throw std::invalid_argument(x);/log_warn(x);/' src/arena_camera_node/src/ArenaCameraNode.cpp \
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
