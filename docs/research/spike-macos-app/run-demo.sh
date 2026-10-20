#!/bin/bash
# ./run-demo.sh ca|smooth|slow|static   (quits any running spike first)
cd "$(dirname "$0")"; pkill SpikeCarrier 2>/dev/null; sleep 1
case "${1:-ca}" in
  ca)     open -n --env SPIKE_CA=1 SpikeCarrier.app ;;   # Core Animation icon capped at 20 fps: ~0% app, WindowServer same as static
  smooth) open -n --env SPIKE_FRAME=0.08 SpikeCarrier.app ;;                                  # SwiftUI MenuBarExtra, ~12 fps (~20% CPU)
  slow)   open -n --env SPIKE_APPKIT=1 --env SPIKE_BAKED=1 --env SPIKE_FRAME=0.5 SpikeCarrier.app ;;  # AppKit status item, 2 fps (~2% CPU); a second, static icon is the SwiftUI one
  static) open -n --env SPIKE_FRAME=99 SpikeCarrier.app ;;
esac
