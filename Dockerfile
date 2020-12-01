FROM ubuntu:focal
LABEL maintainer="Niklas Dörfler <niklas@doerfler-el.de>"

ENV SQUEEZE_VOL /srv/squeezebox
ENV SQUEEZEBOX_VERSION 8.0.0
ENV LANG C.UTF-8
ENV DEBIAN_FRONTEND noninteractive
ENV LATEST_PACKAGE_VERSION_URL=http://www.mysqueezebox.com/update/?version=${SQUEEZEBOX_VERSION}&revision=1&geturl=1&os=deb

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
        pulseaudio && \
    apt-get clean

RUN PACKAGE_DOWNLOAD_URL=$(curl "${LATEST_PACKAGE_VERSION_URL}" | sed 's/_all\.deb/_amd64\.deb/') && \
    curl -Lsf -o /tmp/logitechmediaserver.deb ${PACKAGE_DOWNLOAD_URL} && \
    dpkg -i /tmp/logitechmediaserver.deb && \
    rm -f /tmp/logitechmediaserver.deb && \
    apt-get clean

RUN userdel squeezeboxserver

VOLUME $SQUEEZE_VOL
EXPOSE 3483 3483/udp 9000 9090

COPY entrypoint.sh /entrypoint.sh
COPY squeezebox-runner.sh /squeezebox-runner.sh
RUN chmod +x /entrypoint.sh /squeezebox-runner.sh
ENTRYPOINT ["/entrypoint.sh"]
