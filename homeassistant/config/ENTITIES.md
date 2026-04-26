# Entity Inventory

The iOS Hub dashboard YAML in `dashboards/views/*.yaml` references a number of
entity IDs that don't exist until the corresponding HA integration is
configured. Use this checklist to track what's been wired up and what still
needs a real entity ID swapped in.

Search the dashboard files for `# TODO` comments — every placeholder is
flagged. Recommended workflow:

1. Set up the integration in HA (Settings → Devices & Services).
2. Note the actual entity_ids HA assigns (Settings → Devices & Services →
   click the device → see entities).
3. Find the matching `# TODO` in `dashboards/views/*.yaml` and replace.
4. Reload the dashboard (Developer Tools → YAML → Reload Lovelace, or
   restart HA).

---

## Lights — Hue Bridge (192.168.1.50)

Integration: **Philips Hue** (built-in). Add via Settings → Devices &
Services → Add Integration → Philips Hue → enter `192.168.1.50`.

For the Lights view's auto-grouping to work, **assign each bulb to an Area**
in HA matching its physical room.

| Placeholder              | Real entity_id | Notes |
|--------------------------|----------------|-------|
| `light.office`           |                | Group or single bulb in Office |
| `light.living_room`      |                | |
| `light.bedroom`          |                | |
| `light.garage`           |                | If any Hue bulbs in garage |

Tip: create a **Hue room/group** per HA area to get clean group entities
(`light.office_group`, etc.).

---

## Air Purifiers — Levoit (VeSync)

Integration: **VeSync** (built-in). Add via Settings → Devices & Services →
Add Integration → VeSync → log in with your VeSync app credentials.

| Placeholder                  | Real entity_id | Notes |
|------------------------------|----------------|-------|
| `fan.bedroom_purifier`       |                | |
| `fan.living_room_purifier`   |                | |
| `fan.office_purifier`        |                | |
| `sensor.*_filter_life*`      | (auto-pulled)  | Filter-life sensors auto-discovered by `auto-entities` |
| `sensor.*_air_quality*`      | (auto-pulled)  | |

---

## Switches & Plugs — Linkind (Zigbee) + iHome (Wi-Fi)

- **Linkind** plugs are Zigbee — require a Zigbee coordinator stick
  (e.g. SkyConnect / SONOFF Dongle) and the **ZHA** or **Zigbee2MQTT**
  integration.
- **iHome** plugs are typically Wi-Fi — older models use the discontinued
  iHome cloud (no longer reliable); newer ones may surface via **Tuya**,
  **SmartLife**, or **HomeKit Controller**. Confirm per device.

| Placeholder              | Real entity_id | Notes |
|--------------------------|----------------|-------|
| `switch.office_plug`     |                | Desk plug, Office room |
| `switch.living_room_lamp`|                | |
| `switch.bedroom_plug`    |                | Nightstand |

The Switches view auto-discovers all `switch.*` entities — these
placeholders only matter for the Rooms view.

---

## Sensors — Temperature

The Home view's room tiles show a temperature pill per room. Sources:

- Hue motion sensors (built-in temp sensor) → `sensor.hue_motion_sensor_*_temperature`
- Reolink doorbell / cameras → no temp
- Standalone Zigbee temp sensors (e.g. Aqara) if you add any

| Placeholder                       | Real entity_id |
|-----------------------------------|----------------|
| `sensor.office_temperature`       | |
| `sensor.living_room_temperature`  | |
| `sensor.bedroom_temperature`      | |
| `sensor.garage_temperature`       | |
| `sensor.outdoor_temperature`      | (e.g. `sensor.<weather>_temperature`) |

---

## Weather

Used by the Home view header and Outdoors section. Pick **one**:

- **Met.no** (built-in, no API key, recommended) → `weather.forecast_home`
- **OpenWeatherMap** (free tier, requires API key) → `weather.openweathermap`
- **National Weather Service** (US only, no key) → `weather.<station>`

| Placeholder      | Real entity_id |
|------------------|----------------|
| `weather.home`   | |

---

## Cameras — Frigate (already configured)

These should already work without changes once the Frigate HACS integration
is installed. Frigate camera names come from `frigate/config/config.yml`.

| Frigate camera | HA camera entity      | HA person sensor                 |
|----------------|-----------------------|----------------------------------|
| `doorbell`     | `camera.doorbell`     | `binary_sensor.doorbell_person`  |
| `garage`       | `camera.garage`       | `binary_sensor.garage_person`    |
| `living_room`  | `camera.living_room`  | `binary_sensor.living_room_person` |
| `office`       | `camera.office`       | `binary_sensor.office_person`    |
| `driveway`     | `camera.driveway`     | `binary_sensor.driveway_person`  |

If Frigate names entities differently in your install, adjust the references
in `views/cameras.yaml` and `views/rooms.yaml`.

---

## Scenes (optional)

The Home view's quick-action chips reference two scenes that don't exist
yet — create them in HA (Settings → Scenes) or leave as no-ops:

- `scene.movie_mode` — dim living room lights, turn off ceiling
- `scene.good_night` — turn off all lights, set bedroom purifier to sleep
