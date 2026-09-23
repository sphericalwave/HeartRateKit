//
//  HRViews.swift
//  HeartRateKit
//
//  Shared heart-rate UI: a tappable pill showing live BPM, a live BPM label,
//  and the scan/connect sheet behind them. Bind them to a `HeartRateMonitor`.
//

import SwiftUI
import CoreBluetooth

/// Compact toolbar readout: signal dot, heart, live BPM. Tap to open the
/// connect sheet; long-press to disconnect when a strap is attached.
/// The reading set inside a filled heart, with a lowercase "bpm" beneath it.
/// Scales as one piece from `size`, so the same badge works as a watch's whole
/// screen or as a readout beside a phone's practice controls.
public struct HeartRateBadge: View {

    private let bpm: Int?
    private let size: CGFloat

    public init(bpm: Int?, size: CGFloat = 130) {
        self.bpm = bpm
        self.size = size
    }

    public var body: some View {
        ZStack {
            Image(systemName: "heart.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.pink)
                .frame(width: size, height: size)
            VStack(spacing: -size * 0.02) {
                Text(bpm.map { "\($0)" } ?? "—")
                    .font(.system(size: size * 0.31, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(.system(size: size * 0.11, weight: .medium))
            }
            .foregroundStyle(.white)
            // The lobes eat the top of the frame, so the reading sits low of
            // centre to land in the body of the shape.
            .offset(y: size * 0.06)
        }
        .animation(.default, value: bpm)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm.map { "\($0) beats per minute" } ?? "No heart rate")
    }
}

public struct HRPill: View {
    @ObservedObject private var monitor: HeartRateMonitor
    @State private var showSheet = false

    public init(monitor: HeartRateMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        Button { showSheet = true } label: {
            HStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .imageScale(.small)
                    .foregroundStyle(monitor.bpm != nil ? .green : .secondary)
                Image(systemName: "heart.fill")
                    .imageScale(.small)
                    .foregroundStyle(.red)
                if let bpm = monitor.bpm {
                    Text("\(bpm)")
                        .monospacedDigit()
                        .font(.callout.bold())
                }
            }
        }
        .contextMenu {
            if monitor.state.isConnected {
                Button(role: .destructive) {
                    monitor.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "bolt.horizontal.circle")
                }
            }
        }
        .sheet(isPresented: $showSheet) {
            HRConnectSheet(monitor: monitor)
        }
    }
}

/// Live BPM readout that updates as the strap streams. Useful where an
/// `@Observable` view model can't observe the Combine-based monitor itself.
public struct LiveBPMLabel: View {
    @ObservedObject private var monitor: HeartRateMonitor

    public init(monitor: HeartRateMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        if let bpm = monitor.bpm {
            Label("\(bpm) bpm", systemImage: "heart.fill")
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.red)
        }
    }
}

/// Scan/connect picker. Scans while open, leaves any live connection intact
/// on dismiss, and offers an explicit disconnect for the attached strap.
public struct HRConnectSheet: View {
    @ObservedObject private var monitor: HeartRateMonitor
    @Environment(\.dismiss) private var dismiss

    public init(monitor: HeartRateMonitor) {
        self.monitor = monitor
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Text(monitor.state.label)
                        .foregroundStyle(.secondary)
                }
                if monitor.state.isConnected {
                    Section {
                        Button(role: .destructive) {
                            monitor.disconnect()
                        } label: {
                            Label("Disconnect", systemImage: "bolt.horizontal.circle")
                        }
                    } footer: {
                        Text("Forgets this strap so it won't reconnect on its own.")
                    }
                }
                Section("Discovered") {
                    if monitor.discovered.isEmpty {
                        Text("Make sure your HR strap is on and not connected to another app. Then tap Scan.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(monitor.discovered, id: \.identifier) { p in
                        Button {
                            monitor.connect(p)
                            dismiss()
                        } label: {
                            HStack {
                                Text(p.name ?? "Unknown")
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Heart Rate")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .onAppear { monitor.startScan() }
            .onDisappear { monitor.stopScan() }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Scan") { monitor.startScan() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview("HRPill") {
    HRPill(monitor: .preview())
        .padding()
}

#Preview("LiveBPMLabel") {
    LiveBPMLabel(monitor: .preview())
        .padding()
}

#Preview("HRConnectSheet") {
    HRConnectSheet(monitor: .preview())
}
#endif
