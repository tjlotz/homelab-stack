# homelab-stack

Docker Compose configuration for **BLACKBOX** — a self-hosted homelab running on a Beelink S12 with Ubuntu Server.

## Services

| Service | Port(s) | Description |
|---------|---------|-------------|
| **Plex** | `32400` (host network) | Media server streaming from NAS |
| **Home Assistant** | `8123` (host network) | Home automation platform |
| **Pi-hole** | `53` (DNS), `8080` (web UI) | Network-wide ad blocking |
| **Frigate** | `5000` (web UI), `8971` (API) | Local NVR with event-based object detection (OpenVINO + Intel Quick Sync) |
| **Mosquitto** | `1883` | MQTT broker for Frigate/HA communication |

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
Reolink E1 Zoom Cameras (.11, .12)
  └── HA Reolink Integration (Baichuan protocol, port 9000)
        └── HA built-in go2rtc (RTSP restream :8554)
              ├── Frigate (object detection + event recording)
              └── HA dashboard (live view)

  Object detection: person, cat, dog
  Hardware decode:  Intel Quick Sync (vaapi, N100 iGPU)
  AI detector:      OpenVINO (CPU)
  Recording:        /mnt/Cameras — events only, 14-day retention

  Home Assistant ◄── Frigate integration (MQTT) ── Frigate

Reolink Doorbell D340B (.10)
  └── Reolink app only (no local API — see Issue #6)
```

- **Home Assistant** is the central hub — Reolink integration connects to E1 Zoom cameras via Baichuan protocol on port 9000
- **HA's built-in go2rtc** restreams camera feeds as RTSP, consumed by both Frigate and HA's dashboard
- **Frigate** handles object detection and event-only recording to NAS
- **Doorbell** is not integrated — battery-powered D340B has no local API. Requires a Reolink Home Hub for HA integration (see [Issue #6](https://github.com/tjlotz/homelab-stack/issues/6))
- **E1 Zoom cameras** require "Basic Services Port" set to `9000` in the Reolink app

### Recording

| Setting | Value |
|---------|-------|
| Continuous recording | Disabled |
| Event recording | High-res main stream (person, animal triggers) |
| Retention | 14 days for event recordings and snapshots |
| Storage | NAS at `/mnt/Cameras` |

### Home Assistant Setup

These integrations are configured via the HA web UI at `http://192.168.1.2:8123`:

1. **Reolink integration** — add each E1 Zoom camera by IP:
   - Settings → Devices & Services → Add Integration → Reolink
   - Enter camera IP, username, and password
   - The integration connects via Baichuan protocol on port 9000
   - Note: the doorbell (D340B) cannot be added — see [Issue #6](https://github.com/tjlotz/homelab-stack/issues/6)

2. **Frigate integration** (via HACS):
   - Install HACS in HA if not already installed
   - Install the Frigate integration from HACS
   - Configure with MQTT (Mosquitto at `192.168.1.2:1883`)
   - All cameras, events, and recordings appear in HA automatically

3. **Mosquitto MQTT broker** — HA connects to the existing Mosquitto container:
   - Settings → Devices & Services → Add Integration → MQTT
   - Broker: `192.168.1.2`, Port: `1883`

## IP Allocation

| Range | Device Type | Current Assignments |
|-------|-------------|---------------------|
| `.2-.9` | Infrastructure | `.2` BLACKBOX, `.3` WD MyCloud NAS |
| `.10-.49` | Cameras | `.10` Doorbell (D340B, Reolink app only), `.11` Garage (E1 Zoom), `.12` Living Room (E1 Zoom) |
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
│       └── config.yml      # Frigate NVR configuration
├── mosquitto/
│   └── config/
│       └── mosquitto.conf  # MQTT broker configuration
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

### Steps

1. Clone the repo:
   ```bash
   sudo git clone <repo-url> /opt/homelab-stack
   cd /opt/homelab-stack
   ```

2. Create your environment file:
   ```bash
   cp .env.example .env
   nano .env
   ```
   Fill in your timezone, Plex claim token (get one at https://www.plex.tv/claim), Pi-hole password, and NAS credentials. Camera credentials are configured via the HA web UI (see Home Assistant Setup above).

3. Run the setup script:
   ```bash
   sudo bash setup.sh
   ```
   This installs Docker, mounts the NAS shares, installs the BLACKBOX MOTD, and blacklists the problematic WiFi driver.

4. Log out and back in (to pick up the `docker` group), then start the stack:
   ```bash
   cd /opt/homelab-stack
   docker compose up -d
   ```

### Accessing Services

| Service | URL |
|---------|-----|
| Plex | `http://192.168.1.2:32400/web` |
| Home Assistant | `http://192.168.1.2:8123` |
| Pi-hole | `http://192.168.1.2:8080/admin` |
| Frigate | `http://192.168.1.2:5000` |

## License

See [LICENSE](LICENSE).
