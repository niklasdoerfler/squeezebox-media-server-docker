#!/bin/bash

snapclient -h pulse --sampleformat 44100:16:* --logsink null --player file \
        | mbuffer -m 500b -P 50 \
        | sox -t raw -r 44100 -c 2 -e signed -b 16 - -t raw - rate -v 44050