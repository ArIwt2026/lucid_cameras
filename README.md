# LUCID Triton + Helios2+ with ROS 2 in Docker

This baseline runs LUCID's Arena ROS 2 driver in Ubuntu 22.04 / ROS 2 Humble.
It is intended for the Triton `TRI032S-CC` and Helios2+ `HTP003S-001` GigE
cameras.

## Downloads required

Download from the [LUCID Downloads Hub](https://thinklucid.com/downloads-hub/),
after signing in:

1. `ArenaSDK_v_1.0.8.60_Linux_x64.tar.gz` (Ubuntu 22.04/24.04, no viewer), or
   the equivalent current Linux x64 SDK.
2. No separate camera driver is required. The ROS 2 driver is cloned during the
   image build from `lucidvisionlabs/arena_camera_ros2`.
3. The `arena_api` Python wheel is optional and is not needed by this C++ ROS 2
   driver. Download it only if Python access to Arena is also required.

Put the SDK archive in `vendor/` and build:

```bash
cp ~/Downloads/ArenaSDK*_Linux_x64.tar.gz vendor/
docker compose build
docker compose run --rm lucid_ros2
```

## Camera network

Connect the cameras to a dedicated Ethernet/2.5GbE interface where possible.
Configure the host interface and cameras in the same subnet. For link-local
operation, LUCID's examples use `169.254.0.1` for the host-side address; use
the actual interface name and camera addresses in your setup. `network_mode:
host` is intentional: GigE Vision discovery and high-rate UDP image traffic
must reach the physical interface directly.

Before starting ROS, verify the cameras with ArenaView or the Arena SDK

The persistent host ARP policy is stored in `config/99-lucid-camera-arp.conf`.
Install it as `/etc/sysctl.d/99-lucid-camera-arp.conf` on a fresh host, then
reload it with `sysctl -p /etc/sysctl.d/99-lucid-camera-arp.conf`.

The project uses ROS domain 0, CycloneDDS, and `config/cyclonedds.xml` for ROS
traffic. Start both camera nodes with `docker compose up -d`; the Triton raw
Bayer stream is debayered to `/lucid/triton/image_color`.
examples on the host. Then, inside the container:

```bash
ros2 run arena_camera_node start --ros-args -p serial:=<camera-serial> \
  -p topic:=/triton/image_raw -p pixelformat:=bayer_rggb8
```

Run a second instance for the Helios2+ with its serial number and a different
topic. Use `ros2 topic list`, `ros2 topic hz /triton/image_raw`, and
`ros2 topic echo /triton/image_raw --once` to validate the stream. Helios2+
3D/ToF-specific pixel formats and point-cloud handling should be selected from
the camera's nodemap after confirming the exact Arena SDK profile.

## Host prerequisites

Install Docker Engine and Compose v2, give the user access to Docker, and
ensure the host firewall permits the camera's GigE Vision UDP traffic. The
container does not need USB device mappings because these models are Ethernet
cameras.

## Important limitation

The SDK is proprietary and login-gated, so it is deliberately not committed to
this repository. The build cannot succeed until the archive is placed in
`vendor/`.
