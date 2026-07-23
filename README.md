# HeartRateKit

Heart rate sourcing (BLE strap, HealthKit, watchOS companion) unified behind one
observable facade, plus ready-made SwiftUI display components.

## Requirements

- iOS 16+ / macOS 14+ / watchOS 10+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/sphericalwave/HeartRateKit.git", branch: "main")
```

## Overview

- `HeartRateSource` — protocol implemented by each data source
- `BLEHeartRateSource` — CoreBluetooth strap source
- `HealthKitHeartRateSource` — HealthKit-backed source
- `WatchHeartRateSource` / `WatchHRStreamer` / `WatchHRShared` — watchOS companion streaming (`WCSession`)
- `HeartRateMonitor` — app-facing facade over a source + `HRRecorder`: live BPM, connection state, discovered devices
- `HRRecorder` — records a BPM stream for later analysis
- `HRResolution` / `HRThrottle` — sampling resolution and throttling for streamed data
- `CompactHRChart`, `HRPill`, `LiveBPMLabel`, `HRConnectSheet` — SwiftUI display/connection components

## Dependencies

None.
