import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let bridge = state.bridge {
                WorkspaceSplitView(bridge: bridge, editor: state.editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Loading abcjs…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !state.warnings.isEmpty {
                Divider()
                Text(state.warnings.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.06))
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .abcPlaybackFinished)) { _ in
            state.isPlaying = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .generate12Keys)) { _ in
            Task { await state.generate12Keys() }
        }
        .onChange(of: state.liveRender) { enabled in
            if enabled { Task { await state.renderNow(concertABC: state.editor.liveText()) } }
        }
        .task {
            guard !CommandLine.arguments.contains("--self-test") else { return }
            await state.startIfNeeded()
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("ABC Sheet Music", systemImage: "music.note.list")
                .font(.headline)

            if state.isBootstrapping {
                ProgressView().controlSize(.small)
            }

            Divider().frame(height: 22)

            Picker("Instrument", selection: $state.instrument) {
                ForEach(Instrument.allCases) { inst in
                    Text(inst.menuTitle).tag(inst)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 240)
            .onChange(of: state.instrument) { _ in
                Task { await state.instrumentChanged() }
            }

            Button("12 Keys") {
                Task { await state.generate12Keys() }
            }

            Divider().frame(height: 22)

            Button {
                Task {
                    if state.isPlaying { await state.stop() }
                    else { await state.play() }
                }
            } label: {
                Label(state.isPlaying ? "Stop" : "Play", systemImage: state.isPlaying ? "stop.fill" : "play.fill")
            }
            .disabled(state.bridge == nil)

            Button("Update Score") {
                Task { await state.renderNow(concertABC: state.editor.liveText()) }
            }
            .keyboardShortcut(.return, modifiers: .command)

            Toggle(isOn: $state.liveRender) {
                Text("Auto-update")
            }

            Picker("Layout", selection: $state.measuresPerLine) {
                Text("1 / line").tag(1)
                Text("2 / line").tag(2)
                Text("4 / line").tag(4)
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .onChange(of: state.measuresPerLine) { _ in
                Task { await state.renderNow(concertABC: state.editor.liveText()) }
            }

            Spacer()

            Button { state.openABC() } label: { Image(systemName: "folder") }
            Button { state.saveABC() } label: { Image(systemName: "square.and.arrow.down") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusBar: some View {
        HStack {
            Text("abcjs \(state.bridgeSignature)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(state.liveRender ? "· Auto-update ON" : "· Auto-update OFF")
                .font(.caption)
                .foregroundStyle(state.liveRender ? .green : .orange)
            Text("· \(state.lastRenderNote)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(state.title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text(state.instrument.statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}