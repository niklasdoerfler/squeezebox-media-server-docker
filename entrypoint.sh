#!/usr/bin/env bash

: ${SQUEEZE_UID:=1000}
: ${SQUEEZE_GID:=1000}

groupadd -g $SQUEEZE_GID squeezeboxserver

useradd -u $SQUEEZE_UID -g $SQUEEZE_GID \
    -d /usr/share/squeezeboxserver/ \
    -c 'Logitech Media Server' \
    squeezeboxserver

if [ "$SQUEEZE_VOL" ] && [ -d "$SQUEEZE_VOL" ]; then
    for subdir in prefs logs cache; do
        mkdir -p $SQUEEZE_VOL/$subdir
    done
fi

if [ "$WAVIN_BACKEND" = "pulse" ]; then
    echo "Enabling pulse backend..."
    cp /var/lib/squeezeboxserver/Plugins/WaveInput/custom-convert.pulse.conf /var/lib/squeezeboxserver/Plugins/WaveInput/custom-convert.conf
fi

if [ "$WAVIN_BACKEND" = "snap" ]; then
    echo "Enabling snap backend..."
    cp /var/lib/squeezeboxserver/Plugins/WaveInput/custom-convert.snap.conf /var/lib/squeezeboxserver/Plugins/WaveInput/custom-convert.conf
fi

chown -R squeezeboxserver:squeezeboxserver $SQUEEZE_VOL

exec runuser -u squeezeboxserver -- /squeezebox-runner.sh "$@"
