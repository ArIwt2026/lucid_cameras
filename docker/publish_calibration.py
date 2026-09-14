#!/usr/bin/env python3
import math
import re

import rclpy
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import CameraInfo, Image
from geometry_msgs.msg import TransformStamped
from tf2_ros.static_transform_broadcaster import StaticTransformBroadcaster


class LucidCalibration(Node):
    def __init__(self):
        super().__init__('lucid_calibration')
        # CameraInfo is paired with the live image; keep only the newest one
        # and use the same sensor-data QoS to avoid a stale reliable queue.
        self.pub = self.create_publisher(
            CameraInfo, '/lucid/triton/camera_info', qos_profile_sensor_data)
        self.tf = StaticTransformBroadcaster(self)
        self.create_subscription(
            Image,
            '/lucid/triton/image_color', self.publish_info, qos_profile_sensor_data)

        # Base Triton calibration from orientation.yml (native full resolution 2048x1536).
        self.base_width = 2048.0
        self.base_height = 1536.0
        self.base_k = [1756.1839799276347, 0.0, 1000.549034385331,
                       0.0, 1753.5095468341844, 774.6422756242935,
                       0.0, 0.0, 1.0]
        self.base_d = [-0.25868894455663544, 0.107732371168495,
                       2.2764054268830472e-05, -0.0012015402613801882,
                       0.010515745128515037]

        # orientation.yml rvec, with translation converted from mm to m.
        q = self.rvec_to_quat([-0.0022779675002177128, 0.012553482932240666,
                               0.00056743931903681])
        t = [0.0009951439060323613 / 1000.0, 50.77449722769215 / 1000.0,
             5.59786378091818 / 1000.0]
        msg = TransformStamped()
        msg.header.stamp = self.get_clock().now().to_msg()
        msg.header.frame_id = 'lucid_triton_color_optical_frame'
        msg.child_frame_id = 'lucid_helios_depth_optical_frame'
        msg.transform.translation.x, msg.transform.translation.y, msg.transform.translation.z = t
        msg.transform.rotation.x, msg.transform.rotation.y, msg.transform.rotation.z, msg.transform.rotation.w = q
        self.tf.sendTransform(msg)

    @staticmethod
    def rvec_to_quat(r):
        a = math.sqrt(sum(v * v for v in r))
        s = math.sin(a / 2.0) / a if a else 0.5
        return (r[0] * s, r[1] * s, r[2] * s, math.cos(a / 2.0))

    def publish_info(self, image):
        sx = image.width / self.base_width
        sy = image.height / self.base_height

        info = CameraInfo()
        info.header.stamp = image.header.stamp
        info.header.frame_id = image.header.frame_id
        info.width = image.width
        info.height = image.height
        info.distortion_model = 'plumb_bob'
        info.d = list(self.base_d)
        info.r = [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]

        fx = self.base_k[0] * sx
        cx = self.base_k[2] * sx
        fy = self.base_k[4] * sy
        cy = self.base_k[5] * sy

        info.k = [fx, 0.0, cx,
                  0.0, fy, cy,
                  0.0, 0.0, 1.0]
        info.p = [fx, 0.0, cx, 0.0,
                  0.0, fy, cy, 0.0,
                  0.0, 0.0, 1.0, 0.0]

        self.pub.publish(info)


rclpy.init()
rclpy.spin(LucidCalibration())
rclpy.shutdown()
