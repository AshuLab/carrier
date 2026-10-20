#!/bin/bash
cd "$(dirname "$0")"
cpusec() { ps -o time= -p $1 2>/dev/null | awk -F'[:.]' 'NF==3 {print $1*60+$2+$3/100; next} NF==4 {print $1*3600+$2*60+$3+$4/100}'; }
WS=$(pgrep -x WindowServer | head -1)
one() { label=$1; shift
  env "$@" SpikeCarrier.app/Contents/MacOS/SpikeCarrier >/dev/null 2>&1 & PID=$!; sleep 6
  if ! kill -0 $PID 2>/dev/null; then echo "$label: process died"; return; fi
  a=$(cpusec $PID); w1=$(cpusec $WS); sleep 25; b=$(cpusec $PID); w2=$(cpusec $WS)
  alive=$(kill -0 $PID 2>/dev/null && echo alive || echo DIED)
  echo "$label: app $(echo "scale=1; ($b - $a) * 100 / 25" | bc)%  WindowServer $(echo "scale=1; ($w2 - $w1) * 100 / 25" | bc)%  ($alive)"
  kill $PID 2>/dev/null; wait $PID 2>/dev/null; sleep 1; }
for round in 1 2; do
  echo "--- round $round"
  one "static, nothing animated        " SPIKE_CA=1 SPIKE_CA_MOTION=none
  one "CA continuous bounce (60 fps)   " SPIKE_CA=1 SPIKE_CA_MOTION=bounce
  one "CA bounce, frame rate range 4fps" SPIKE_CA=1 SPIKE_CA_MOTION=bounce SPIKE_CA_FPS=4
  one "CA bounce, discrete 3 steps/s   " SPIKE_CA=1 SPIKE_CA_MOTION=bounce SPIKE_CA_STEPS=3
  one "CA bounce, discrete 1 step/s    " SPIKE_CA=1 SPIKE_CA_MOTION=bounce SPIKE_CA_STEPS=1
  one "AppKit image swap, 2 fps        " SPIKE_APPKIT=1 SPIKE_BAKED=1 SPIKE_FRAME=0.5
done
echo DONE
