# DS-Hotspot
### A Docker container that creates a DS-compatible WEP hotspot while restricting network access to Wiimmfi servers only.

/!\ Stop the container when not in use. This still uses WEP.

## Requirements

- Linux host (Windows and macOS are untested.)
- Docker
- Wi-Fi adapter that supports AP mode (run `iw list` to check)
- `hostapd` compatible driver (usually `nl80211`)

## Usage

Use this compose file to start the container:

```yaml
services:
  ds-hotspot:
    image: ghcr.io/sdhemily/ds-hotspot:latest
    container_name: ds-hotspot
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      UPLINK_IFACE: eth0
      HOTSPOT_IFACE: wlan0
      DS_MAC_ADDR: 00:11:22:33:44:55 # /!\ IMPORTANT - Set this to your DSes MAC Address! 
    volumes:
      - ./hostapd.conf:/etc/hostapd/hostapd.conf:ro
    devices: 
      - /dev/rfkill:/dev/rfkill
    restart: unless-stopped
```
## hostapd config
You need to create a `hostapd.conf` compatible with your wireless adapter and mount it to `/etc/hostapd/hostapd.conf`