#!/bin/sh
set -e

VERSION="${VERSION:-(Unknown Version)}"
echo "[*] DS-Hotspot $VERSION"

HOSTAPD_ARGS=""
DNSMASQ_ARGS=""
HOTSPOT_IFACE="${HOTSPOT_IFACE:-wlan0}"
UPLINK_IFACE="${UPLINK_IFACE:-eth0}"
HOTSPOT_IP="${HOTSPOT_IP:-172.31.255.1}"
HOTSPOT_CIDR="${HOTSPOT_IP}/24"
HOTSPOT_SUBNET="${HOTSPOT_SUBNET:-172.31.255.0/24}"
CHAIN_NAME="DS_HOTSPOT"

if [ "${VERBOSE_LOGGING:-0}" = "1" ]; then
    HOSTAPD_ARGS="-d"
    DNSMASQ_ARGS="--log-dhcp --log-queries"
fi

if [ -z "${DS_MAC_ADDR:-}" ]; then
    echo "[!] MAC Address not set. Please set the environment variable DS_MAC_ADDR."
    exit 1
fi

# config files

echo "$DS_MAC_ADDR" > /etc/hostapd/accept
chmod 600 /etc/hostapd/accept
cat > /etc/dnsmasq.conf <<EOF
interface=${HOTSPOT_IFACE}
bind-dynamic
dhcp-range=${HOTSPOT_IP%.*}.10,${HOTSPOT_IP%.*}.10,255.255.255.0,1h
dhcp-option=1,255.255.255.0
dhcp-option=3,${HOTSPOT_IP}
dhcp-option=6,${HOTSPOT_IP}
dhcp-authoritative
dhcp-no-override
no-ping
no-resolv
server=167.235.229.36
EOF

# cleanup functions 

cleanup() {
    echo "[*] Clearing the firewall state..."
    iptables -D FORWARD -s "$HOTSPOT_SUBNET" -j "$CHAIN_NAME" 2>/dev/null || true
    iptables -D FORWARD \
        -d "$HOTSPOT_SUBNET" \
        -m conntrack --ctstate ESTABLISHED,RELATED \
        -j ACCEPT 2>/dev/null || true
    iptables -F "$CHAIN_NAME" 2>/dev/null || true
    iptables -X "$CHAIN_NAME" 2>/dev/null || true
    iptables -t nat -D POSTROUTING \
        -s "$HOTSPOT_SUBNET" \
        -o "$UPLINK_IFACE" \
        -j MASQUERADE 2>/dev/null || true
}

quit() {
    echo "[*] Quitting..."
    kill "$DNSMASQ_PID" 2>/dev/null || true
    kill "$HOSTAPD_PID" 2>/dev/null || true
    cleanup
    ip addr flush dev "$HOTSPOT_IFACE" 2>/dev/null || true
}

trap quit EXIT SIGINT SIGTERM

# conf interface

echo "[*] Configuring interface..."
ip link set "$HOTSPOT_IFACE" down 2>/dev/null || true
ip addr flush dev "$HOTSPOT_IFACE"
ip addr add "$HOTSPOT_CIDR" dev "$HOTSPOT_IFACE"
ip link set "$HOTSPOT_IFACE" up

# firewall setup

cleanup
echo "[*] Configuring firewall..."
iptables -N "$CHAIN_NAME" 2>/dev/null || iptables -F "$CHAIN_NAME"
iptables -C FORWARD \
    -d "$HOTSPOT_SUBNET" \
    -m conntrack --ctstate ESTABLISHED,RELATED \
    -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 \
    -d "$HOTSPOT_SUBNET" \
    -m conntrack --ctstate ESTABLISHED,RELATED \
    -j ACCEPT
iptables -C FORWARD \
    -s "$HOTSPOT_SUBNET" \
    -j "$CHAIN_NAME" 2>/dev/null || \
iptables -I FORWARD 1 \
    -s "$HOTSPOT_SUBNET" \
    -j "$CHAIN_NAME"

echo "[*] Fetching WiiLink hosts..."
TMP_ALLOWLIST="/tmp/wiilink-hosts.txt"
curl -fsSL "https://raw.githubusercontent.com/WiiLink24/DNS-Server/refs/heads/master/dns_zones-hosts.txt" -o "$TMP_ALLOWLIST"
awk '{print $1}' "$TMP_ALLOWLIST" | sort -u > /tmp/allowed_ips.txt

iptables -C "$CHAIN_NAME" \
    -s "$HOTSPOT_SUBNET" \
    -d "$HOTSPOT_IP" \
    -p udp \
    --dport 53 \
    -j ACCEPT 2>/dev/null || \
iptables -A "$CHAIN_NAME" \
    -s "$HOTSPOT_SUBNET" \
    -d "$HOTSPOT_IP" \
    -p udp \
    --dport 53 \
    -j ACCEPT
iptables -C "$CHAIN_NAME" \
    -s "$HOTSPOT_SUBNET" \
    -d "$HOTSPOT_IP" \
    -p tcp \
    --dport 53 \
    -j ACCEPT 2>/dev/null || \
iptables -A "$CHAIN_NAME" \
    -s "$HOTSPOT_SUBNET" \
    -d "$HOTSPOT_IP" \
    -p tcp \
    --dport 53 \
    -j ACCEPT
iptables -C INPUT \
    -i "$HOTSPOT_IFACE" \
    -p udp \
    --dport 67 \
    -j ACCEPT 2>/dev/null || \
iptables -A INPUT \
    -i "$HOTSPOT_IFACE" \
    -p udp \
    --dport 67 \
    -j ACCEPT
iptables -C OUTPUT \
    -o "$HOTSPOT_IFACE" \
    -p udp \
    --sport 67 \
    -j ACCEPT 2>/dev/null || \
iptables -A OUTPUT \
    -o "$HOTSPOT_IFACE" \
    -p udp \
    --sport 67 \
    -j ACCEPT

while read -r ip; do
    echo "[*] Allowing $ip"
    iptables -C "$CHAIN_NAME" \
        -s "$HOTSPOT_SUBNET" \
        -d "$ip" \
        -j ACCEPT 2>/dev/null || \
    iptables -A "$CHAIN_NAME" \
        -s "$HOTSPOT_SUBNET" \
        -d "$ip" \
        -j ACCEPT
done < /tmp/allowed_ips.txt

iptables -C "$CHAIN_NAME" -d 10.0.0.0/8 -j DROP 2>/dev/null || \
iptables -A "$CHAIN_NAME" -d 10.0.0.0/8 -j DROP
iptables -C "$CHAIN_NAME" -d 172.16.0.0/12 -j DROP 2>/dev/null || \
iptables -A "$CHAIN_NAME" -d 172.16.0.0/12 -j DROP
iptables -C "$CHAIN_NAME" -d 192.168.0.0/16 -j DROP 2>/dev/null || \
iptables -A "$CHAIN_NAME" -d 192.168.0.0/16 -j DROP
iptables -C "$CHAIN_NAME" -j DROP 2>/dev/null || \
iptables -A "$CHAIN_NAME" -j DROP

# block ipv6 just in case a leak could happen

ip6tables -C INPUT -i "$HOTSPOT_IFACE" -j DROP 2>/dev/null || \
ip6tables -A INPUT -i "$HOTSPOT_IFACE" -j DROP
ip6tables -C FORWARD -i "$HOTSPOT_IFACE" -j DROP 2>/dev/null || \
ip6tables -A FORWARD -i "$HOTSPOT_IFACE" -j DROP

iptables -t nat -C POSTROUTING \
    -s "$HOTSPOT_SUBNET" \
    -o "$UPLINK_IFACE" \
    -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING \
    -s "$HOTSPOT_SUBNET" \
    -o "$UPLINK_IFACE" \
    -j MASQUERADE

# start everything

echo "[*] Starting hostapd..."
hostapd $HOSTAPD_ARGS /etc/hostapd/hostapd.conf & HOSTAPD_PID=$!
echo "[*] Starting dnsmasq..."
dnsmasq $DNSMASQ_ARGS -d -C /etc/dnsmasq.conf & DNSMASQ_PID=$!

while kill -0 "$HOSTAPD_PID" 2>/dev/null &&
    kill -0 "$DNSMASQ_PID" 2>/dev/null; do
    sleep 1
done

echo "[!] A service exited unexpectedly"
exit 1