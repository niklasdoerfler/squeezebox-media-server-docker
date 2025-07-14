#!/usr/bin/env bash

if [ "$SQUEEZE_VOL" ] && [ -d "$SQUEEZE_VOL" ]; then
    for subdir in prefs logs cache; do
        mkdir -p $SQUEEZE_VOL/$subdir
    done
fi

if [ "$WAVIN_BACKEND" = "pulse" ]; then
    echo "Enabling pulse backend..."
    cp /lms/Plugins/WaveInput/stream_worker_pulse.sh /lms/Plugins/WaveInput/stream_worker.sh
fi

if [ "$WAVIN_BACKEND" = "snap" ]; then
    echo "Enabling snap backend..."
    cp /lms/Plugins/WaveInput/stream_worker_snap.sh /lms/Plugins/WaveInput/stream_worker.sh
fi

exec /squeezebox-runner.sh "$@"
