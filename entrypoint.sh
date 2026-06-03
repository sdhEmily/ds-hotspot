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
HOTSPOT_SUBNET="$(echo "$HOTSPOT_IP" | cut -d. -f1-3).0/24"
DNS_SERVER="${DNS_SERVER:-167.235.229.36}"
CHAIN_NAME="DS_HOTSPOT"

if [ "${VERBOSE:-0}" = "1" ]; then
    HOSTAPD_ARGS="-d"
    DNSMASQ_ARGS="--log-dhcp --log-queries"
fi

if [ -z "${HOSTAPD_CONF:-}" ]; then
    echo "[!] hostapd config missing. Please set HOSTAPD_CONF."
    exit 1
fi

mkdir -p /etc/hostapd
echo -e "interface=$HOTSPOT_IFACE\n$HOSTAPD_CONF" > /etc/hostapd/hostapd.conf

cat > /etc/dnsmasq.conf <<EOF
interface=${HOTSPOT_IFACE}
bind-dynamic
dhcp-range=${HOTSPOT_IP%.*}.10,${HOTSPOT_IP%.*}.254,255.255.255.0,1h
dhcp-option=1,255.255.255.0
dhcp-option=3,${HOTSPOT_IP}
dhcp-option=6,${HOTSPOT_IP}
dhcp-authoritative
dhcp-no-override
no-ping
no-resolv
server=$DNS_SERVER
EOF

# cleanup functions 

cleanup() {
    echo "[*] Clearing the firewall state..."
    iptables -D FORWARD -s "$HOTSPOT_SUBNET" -j "$CHAIN_NAME" 2>/dev/null || true
    iptables -D FORWARD -d "$HOTSPOT_SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -F "$CHAIN_NAME" 2>/dev/null || true
    iptables -X "$CHAIN_NAME" 2>/dev/null || true
    iptables -t nat -D POSTROUTING -s "$HOTSPOT_SUBNET" -o "$UPLINK_IFACE" -j MASQUERADE 2>/dev/null || true
    ip6tables -D INPUT -i "$HOTSPOT_IFACE" -j DROP -m comment --comment "ds-hotspot" 2>/dev/null || true
    ip6tables -D FORWARD -i "$HOTSPOT_IFACE" -j DROP -m comment --comment "ds-hotspot" 2>/dev/null || true
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
iptables -I FORWARD 1 -d "$HOTSPOT_SUBNET" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -I FORWARD 1 -s "$HOTSPOT_SUBNET" -j "$CHAIN_NAME"

echo "[*] Resolving WFC IPs..."
while read -r domain; do
    dig @"$DNS_SERVER" +short "$domain"
done < /urls | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u > /tmp/allowed_ips.txt

if ! grep -q '[0-9]' /tmp/allowed_ips.txt; then
    echo "[!] No IPs in list! Exiting."
    exit 1
fi

iptables -A "$CHAIN_NAME" -s "$HOTSPOT_SUBNET" -d "$HOTSPOT_IP" -p udp --dport 53 -j ACCEPT
iptables -A "$CHAIN_NAME" -s "$HOTSPOT_SUBNET" -d "$HOTSPOT_IP" -p tcp --dport 53 -j ACCEPT
iptables -A "$CHAIN_NAME" -s "$HOTSPOT_SUBNET" -d "$DNS_SERVER" -j ACCEPT

while read -r ip; do
    echo "[*] Allowing $ip"
    iptables -A "$CHAIN_NAME" -s "$HOTSPOT_SUBNET" -d "$ip" -j ACCEPT
done < /tmp/allowed_ips.txt

iptables -A "$CHAIN_NAME" -j DROP
ip6tables -A INPUT -i "$HOTSPOT_IFACE" -j DROP -m comment --comment "ds-hotspot"
ip6tables -A FORWARD -i "$HOTSPOT_IFACE" -j DROP -m comment --comment "ds-hotspot"

iptables -t nat -A POSTROUTING -s "$HOTSPOT_SUBNET" -o "$UPLINK_IFACE" -j MASQUERADE

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