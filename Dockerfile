FROM ubuntu:focal
LABEL maintainer="Niklas Dörfler <niklas@doerfler-el.de>"

ENV SQUEEZE_VOL /srv/squeezebox
ENV SQUEEZEBOX_VERSION 8.2.0
ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV LATEST_PACKAGE_VERSION_URL=https://www.mysqueezebox.com/update/?version=${SQUEEZEBOX_VERSION}&revision=1&geturl=1&os=deb
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
        libpangoxft-1.0-0 \
        libpangox-1.0-0 \
        libavahi-client3 \
        libcrypt-openssl-rsa-perl \
        xauth && \
    apt-get clean

RUN PACKAGE_DOWNLOAD_URL=$(curl "${LATEST_PACKAGE_VERSION_URL}" | sed 's/_all\.deb/_amd64\.deb/') && \
    curl -Lsf -o /tmp/logitechmediaserver.deb ${PACKAGE_DOWNLOAD_URL} && \
    dpkg -i /tmp/logitechmediaserver.deb && \
    rm -f /tmp/logitechmediaserver.deb && \
    apt-get clean

RUN export DOWNLOAD_URL=$(curl -s https://api.github.com/repos/badaix/snapcast/releases/latest | grep "browser_download_url.*snapclient.*_amd64.deb" | cut -d '"' -f 4 | head -n 1) && wget "${DOWNLOAD_URL}" -O 'snapclient.deb' && \
    apt install -y ./snapclient.deb && \
    rm snapclient.deb

COPY waveinput/ /var/lib/squeezeboxserver/Plugins/WaveInput/

RUN userdel squeezeboxserver

VOLUME $SQUEEZE_VOL
EXPOSE 3483 3483/udp 9000 9090

COPY entrypoint.sh /entrypoint.sh
COPY squeezebox-runner.sh /squeezebox-runner.sh
RUN chmod +x /entrypoint.sh /squeezebox-runner.sh
ENTRYPOINT ["/entrypoint.sh"]
