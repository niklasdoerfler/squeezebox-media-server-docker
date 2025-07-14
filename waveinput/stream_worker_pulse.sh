#!/bin/bash

parec --format=s16le --file-format=raw --raw --rate=44100 --channels=2 --device=Snapcast.monitor --client-name=lms_$(date +"%Y_%m_%d_%H_%M_%S") --process-time-msec=1 --latency-msec=1 \
        | mbuffer -m 500b -P 50 \
        | sox -t raw -r 44100 -c 2 -e signed -b 16 - -t raw - rate -v 44050