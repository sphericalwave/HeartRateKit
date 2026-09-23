# HeartRateKit

Heart rate sourcing (BLE strap, HealthKit, watchOS companion) unified behind one
observable facade, plus ready-made SwiftUI display components.

## Components

<!-- SCREENSHOTS:START -->
| Component | Preview |
| --- | --- |
| `CompactHRChart` | ![CompactHRChart](Docs/img/compact-hr-chart.png) |
| `HRConnectSheet` | ![HRConnectSheet](Docs/img/hr-connect-sheet.png) |
| `HRPill` | ![HRPill](Docs/img/hr-pill.png) |
| `LiveBPMLabel` | ![LiveBPMLabel](Docs/img/live-bpm-label.png) |
<!-- SCREENSHOTS:END -->

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
- `HeartRateBadge` — the reading inside a filled heart with a lowercase "bpm" beneath, scaling as one piece from `size`
- `HeartRateMonitor` — app-facing facade over a source + `HRRecorder`: live BPM, connection state, discovered devices. `use(.ble)` / `use(.watch)` swaps which source feeds it; everything downstream reads the same either way. `setWatchResolution(_:)` sets the watch's forwarding density.
- `HRRecorder` — records a BPM stream for later analysis
- `HRResolution` / `HRThrottle` — sampling resolution and throttling for streamed data
- `CompactHRChart`, `HRPill`, `LiveBPMLabel`, `HRConnectSheet` — SwiftUI display/connection components

## Dependencies

None.
