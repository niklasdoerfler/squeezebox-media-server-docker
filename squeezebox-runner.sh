#!/usr/bin/env bash

myip=$(ip addr show eth0 2>/dev/null | awk '$1 == "inet" {print $2}' | cut -f1 -d/)

if [ "${myip}" ]; then
    url="http://${myip}:9000/"

    echo ======================================================================
    echo Squeezebox server is running.
    echo URL: "${url}"
    echo ======================================================================
    echo
fi

exec squeezeboxserver \
    --prefsdir $SQUEEZE_VOL/prefs \
    --logdir $SQUEEZE_VOL/logs \
    --cachedir $SQUEEZE_VOL/cache "$@"
