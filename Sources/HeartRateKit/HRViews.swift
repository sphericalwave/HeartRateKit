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
