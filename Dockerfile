FROM alpine:3.23 AS builder

RUN apk add --no-cache \
    build-base \
    linux-headers \
    pkgconfig \
    libnl3-dev \
    openssl-dev \
    wget

WORKDIR /build

RUN wget https://w1.fi/releases/hostapd-2.11.tar.gz && \
    tar xzf hostapd-2.11.tar.gz

WORKDIR /build/hostapd-2.11/hostapd

RUN cp defconfig .config && \
    echo "CONFIG_WEP=y" >> .config && \
    echo "CONFIG_DRIVER_NL80211=y" >> .config && \
    echo "CONFIG_LIBNL32=y" >> .config && \
    make -j$(nproc)

RUN strip hostapd

FROM alpine:3.23

ARG VERSION=unknown
ENV VERSION=$VERSION

RUN apk add --no-cache \
    dnsmasq \
    iptables \
    ip6tables \
    iproute2 \
    curl \
    libnl3

COPY --from=builder \
    /build/hostapd-2.11/hostapd/hostapd \
    /usr/local/bin/hostapd

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]