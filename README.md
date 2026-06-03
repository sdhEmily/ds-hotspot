# DS-Hotspot
### A Docker container that creates a DS-compatible WEP hotspot while restricting network access to WFC servers only.

## Requirements

- Linux host (Windows and macOS are untested)
- Docker
- Wi-Fi adapter that supports AP mode (run `iw list` to check)

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
      # This is an example config and will most likely NOT work for your adapter
      # This has been configured for a Realtek RTL8188FU chipset.
      # Interface is automatically set to HOTSPOT_IFACE so there is no need to include it.
      HOSTAPD_CONF: |
        driver=nl80211

        ssid=DS-Hotspot
        wep_default_key=0
        wep_key0=112233445566778899aabbccdd

        channel=6
        wmm_enabled=0
        auth_algs=1
        ignore_broadcast_ssid=0
        max_num_sta=1
    devices: 
      - /dev/rfkill:/dev/rfkill
    restart: unless-stopped

```
## Environment Variables

|Name|Default Value|Description|
|----------|:-------------:|------:|
|**VERBOSE**|0|Set to 1 for verbose logging of hostapd and dnsmasq.|
|**UPLINK_IFACE**|eth0|Network interface that is connected to the internet.|
|**HOTSPOT_IFACE**|wlan0|Wireless network interface that supports Access Point mode.|
|**HOTSPOT_IP**|172.31.255.1|Local IP for the hotspot.|
|**DNS_SERVER**|167.235.229.36|DNS server that points to a WFC service. (WiiLink WFC, Wiimmfi. etc.).
|**HOSTAPD_CONF**|...|hostapd.conf file configured to your wifi adapter. See above.|
