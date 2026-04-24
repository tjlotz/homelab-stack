# homelab-stack

Docker Compose configuration for **BLACKBOX** — a self-hosted homelab running on a Beelink S12 with Ubuntu Server.

## Services

| Service | Port(s) | Description |
|---------|---------|-------------|
| **Plex** | `32400` (host network) | Media server streaming from NAS |
| **Home Assistant** | `8123` (host network) | Home automation platform |
| **Pi-hole** | `53` (DNS), `8080` (web UI) | Network-wide ad blocking |
| **Frigate** | `5000` (web UI), `8554` (RTSP), `8555` (WebRTC), `8971` (auth API) | Local NVR with event-based object detection (OpenVINO + Intel Quick Sync). Authentication enabled. |
| **Mosquitto** | `1883` | MQTT broker for Frigate ↔ HA. Authentication required. |

## Hardware

- **Server:** [Beelink S12](https://amazon.com/dp/B0BVFS94J5) (Ubuntu Server 24.04, headless)
- **Storage:** WD MyCloud NAS at `192.168.1.3`
  - `Public/Media/Movies` mounted at `/mnt/Public/Media/Movies`
  - `Public/Media/TV Shows` mounted at `/mnt/Public/Media/TV Shows`
  - `Cameras` share mounted at `/mnt/Cameras` (security footage, authenticated)
- **Static IP:** `192.168.1.2`

## Camera System

### Architecture

```
Reolink Cameras (RTSP :554)
  ├── Doorbell    192.168.1.10  (D340W, wired)
  ├── Garage      192.168.1.11  (E1 Pro)
  ├── Living Room 192.168.1.12  (E1 Pro)
  ├── Office      192.168.1.13  (E1 Pro)
  └── Driveway    192.168.1.14  (Lumus Pro E450)
        │
        └── Frigate (bundled go2rtc — single RTSP connection per camera)
              ├── Detect: sub-stream @ 640x480 5fps, OpenVINO
              ├── Record: main-stream + audio, event-only
              ├── Decode: Intel Quick Sync (vaapi, N100 iGPU)
              ├── Storage: /mnt/Cameras (4-day rolling retention)
              └── MQTT (authenticated) ── Home Assistant (Frigate HACS integration)
```

- **Frigate** is the single video pipeline. Cameras connect via native RTSP — no HA Reolink integration, no go2rtc HA add-on.
- **Bundled go2rtc** inside Frigate centralizes camera connections (one connection per camera, restreamed for both detect and record roles).
- **Home Assistant** consumes cameras, events, and recordings via the Frigate HACS integration over authenticated MQTT.
- **Object detection:** `person`, `cat`, `dog`. Recording triggers only on these.
- **Audio** is captured on event clips.

### Recording

| Setting | Value |
|---------|-------|
| Continuous recording | Disabled |
| Event recording | High-res main stream + audio (person, cat, dog triggers) |
| Retention | 4-day rolling window for events and snapshots (`mode: active_objects`). Cleanup runs daily, so footage age oscillates between ~72h and ~96h. |
| Storage | NAS at `/mnt/Cameras` |

### Camera Setup

Each Reolink camera must be configured (via the Reolink phone app) with:

- **Static IP** in the `.10–.13` range (see IP Allocation below)
- **Admin user:** `admin`
- **Admin password:** the same shared password set in `.env` as `REOLINK_PASS` (20+ char alphanumeric, stored in your password manager)
- **RTSP enabled** (default on D340W and E1 Pro)

### Home Assistant Setup

Configured via the HA web UI at `http://192.168.1.2:8123`:

1. **MQTT integration** — connect HA to Mosquitto:
   - Settings → Devices & Services → Add Integration → MQTT
   - Broker: `192.168.1.2`, Port: `1883`
   - Username: `admin`, Password: matches `MQTT_PASS` in `.env`

2. **Frigate integration** (via HACS):
   - Install HACS in HA if not already installed
   - Install the Frigate integration from HACS
   - Point it at `http://192.168.1.2:5000`
   - All cameras, events, and recordings appear in HA automatically

The previous HA Reolink integration is no longer used — remove it from Settings → Devices & Services if present. Also remove any `go2rtc:` block from `/config/configuration.yaml` (added during the prior Baichuan-based attempt; no longer needed).

### Security

- All services are **LAN-only**. No port forwarding for the camera stack.
- **MQTT** requires authentication (`admin` + password from `.env`, hashed into `mosquitto/config/passwd` by `setup.sh`).
- **Frigate web UI** requires authentication (set up on first login at `:5000`).
- **`.env`** holds plaintext secrets — kept `chmod 600` and gitignored. Acceptable for a single-host LAN deployment; revisit if remote access changes the threat model.
- **Deferred** (tracked in GitHub issues):
  - Block Reolink cameras from WAN egress at the router (Issue #7).

## Remote Access

Remote access to BLACKBOX services is handled by [Tailscale](https://tailscale.com), a zero-config WireGuard-based VPN. Tailscale runs natively on the host (not in Docker) and acts as a **subnet router** for the LAN, so client devices on the tailnet can reach all services — including Reolink cameras, which can't run a Tailscale client themselves.

### Architecture

- Tailscale installed via the official apt repo by `setup.sh`.
- Hostname: `blackbox`. With MagicDNS enabled, services are reachable at `blackbox.<your-tailnet>.ts.net`.
- Subnet route: `192.168.1.0/24` advertised from `blackbox`, gated by approval in the Tailscale admin console.
- Node tag: `tag:server` (so the node is owned by the tailnet rather than a personal user account).
- IPv4 forwarding enabled in `/etc/sysctl.d/99-tailscale.conf`. IPv6 forwarding intentionally left off (LAN devices we route to are IPv4-only).
- Default tailnet ACL (single user, all-allow). No exit node.

### One-time bring-up

After `setup.sh` finishes installing Tailscale:

```bash
sudo tailscale up \
  --hostname=blackbox \
  --advertise-routes=192.168.1.0/24 \
  --advertise-tags=tag:server
```

Then in the [Tailscale admin console](https://login.tailscale.com/admin/):

1. **ACL policy** — define `tag:server` with your user as the owner (required before the tag can be assigned).
2. **Subnet routes** — approve the `192.168.1.0/24` route advertised by `blackbox`.
3. **Key expiry** — disable for the `blackbox` node so the server doesn't drop off the tailnet every 90 days.
4. **MagicDNS** — enable under DNS settings.

### Accessing services remotely

Once the node is up, joined to the tailnet, and approved, install the Tailscale client on any device (phone, laptop) and sign in to the same tailnet. Services are reachable at:

| Service | URL over Tailscale |
|---------|--------------------|
| Home Assistant | `http://blackbox.<tailnet>.ts.net:8123` |
| Plex | `http://blackbox.<tailnet>.ts.net:32400/web` |
| Frigate | `http://blackbox.<tailnet>.ts.net:5000` |
| Reolink cameras | `http://192.168.1.10`–`.14` (via the subnet route) |

Adding a new client device: install Tailscale, sign in to the same tailnet, and you're done — no per-service configuration needed.

## IP Allocation

| Range | Device Type | Current Assignments |
|-------|-------------|---------------------|
| `.2-.9` | Infrastructure | `.2` BLACKBOX, `.3` WD MyCloud NAS |
| `.10-.49` | Cameras | `.10` Doorbell (D340W), `.11` Garage (E1 Pro), `.12` Living Room (E1 Pro), `.13` Office (E1 Pro) |
| `.50-.99` | Lights | |
| `.100-.149` | Switches/Plugs | |
| `.150-.199` | Air Purifiers | |
| `.200-.254` | Reserved | |

## Directory Structure

```
homelab-stack/
├── docker-compose.yml      # Service definitions
├── .env.example            # Environment variable template
├── setup.sh                # One-time server bootstrap script
├── motd/
│   └── blackbox-motd.sh    # SSH login banner
├── frigate/
│   └── config/
│       └── config.yml      # Frigate NVR configuration (cameras, retention, go2rtc)
├── mosquitto/
│   └── config/
│       ├── mosquitto.conf  # MQTT broker configuration (auth required)
│       └── passwd          # Hashed MQTT credentials (gitignored, generated by setup.sh)
├── plex/config/            # Plex persistent data (gitignored)
├── homeassistant/config/   # Home Assistant persistent data (gitignored)
└── pihole/
    ├── etc-pihole/         # Pi-hole persistent data (gitignored)
    └── etc-dnsmasq.d/      # Pi-hole DNS config (gitignored)
```

## Setup

### Prerequisites

- Fresh Ubuntu Server 24.04 install
- Ethernet connection
- WD MyCloud NAS accessible at `192.168.1.3`
- Reolink cameras configured with static IPs and the shared admin password

### Steps

1. Clone the repo:
   ```bash
   sudo git clone <repo-url> /opt/homelab-stack
   cd /opt/homelab-stack
   ```

2. Create your environment file:
   ```bash
   cp .env.example .env
   chmod 600 .env
   nano .env
   ```
   Fill in: timezone, Plex claim token (https://www.plex.tv/claim), Pi-hole password, NAS credentials, Reolink admin password, MQTT password.

3. Run the setup script:
   ```bash
   sudo bash setup.sh
   ```
   This installs Docker and Tailscale, mounts NAS shares, installs the BLACKBOX MOTD, blacklists the problematic WiFi driver, enables IPv4 forwarding for Tailscale subnet routing, and generates the hashed Mosquitto password file.

4. Log out and back in (to pick up the `docker` group), then start the stack:
   ```bash
   cd /opt/homelab-stack
   docker compose up -d
   ```

5. Join the tailnet (one-time):
   ```bash
   sudo tailscale up \
     --hostname=blackbox \
     --advertise-routes=192.168.1.0/24 \
     --advertise-tags=tag:server
   ```
   Follow the printed URL to authenticate. Then complete the Tailscale admin console steps in the [Remote Access](#remote-access) section above (define `tag:server`, approve the subnet route, disable key expiry, enable MagicDNS).

6. In the HA UI, configure the MQTT and Frigate integrations (see Home Assistant Setup above).

### Accessing Services

| Service | URL |
|---------|-----|
| Plex | `http://192.168.1.2:32400/web` |
| Home Assistant | `http://192.168.1.2:8123` |
| Pi-hole | `http://192.168.1.2:8080/admin` |
| Frigate | `http://192.168.1.2:5000` (auth required) |

## License

See [LICENSE](LICENSE).
