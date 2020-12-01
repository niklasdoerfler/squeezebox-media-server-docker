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

chown -R squeezeboxserver:squeezeboxserver $SQUEEZE_VOL

exec runuser -u squeezeboxserver -- /start-squeezebox.sh "$@"
