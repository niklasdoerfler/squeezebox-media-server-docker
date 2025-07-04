FROM ghcr.io/lms-community/lyrionmusicserver:9.0.3
LABEL maintainer="Niklas Dörfler <niklas@doerfler-el.de>"

ENV WAVIN_BACKEND pulse
ENV WAVIN_SNAPSERVER_HOST pulse
ENV WAVIN_PULSEAUDIO_SERVER pulse

RUN apt-get update && \
    apt-get -y install \
        curl \
        wget \
        nano \
        faad \
        flac \
        lame \
        sox \
        libio-socket-ssl-perl \
        tzdata \
        pulseaudio \
        libavahi-client3 \
        libcrypt-openssl-rsa-perl \
        xauth && \
    apt-get clean

ARG SNAPCLIENT_VERSION="0.31.0"
RUN export DOWNLOAD_URL="https://github.com/badaix/snapcast/releases/download/v${SNAPCLIENT_VERSION}/snapclient_${SNAPCLIENT_VERSION}-1_amd64_bookworm_with-pulse.deb" && wget "${DOWNLOAD_URL}" -O 'snapclient.deb' && \
    apt install -y ./snapclient.deb && \
    rm snapclient.deb

COPY waveinput/ /lms/Plugins/WaveInput/

EXPOSE 3483 3483/udp 9000 9090

COPY entrypoint.sh /entrypoint.sh
COPY squeezebox-runner.sh /squeezebox-runner.sh
RUN chmod +x /entrypoint.sh /squeezebox-runner.sh
ENTRYPOINT ["/entrypoint.sh"]
