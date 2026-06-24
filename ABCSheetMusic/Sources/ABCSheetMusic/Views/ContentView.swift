import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                editorPane
                    .frame(minWidth: 280, idealWidth: 360, maxWidth: 520)
                ScoreWebView(bridge: state.bridge)
                    .frame(minWidth: 400)
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .abcPlaybackFinished)) { _ in
            state.isPlaying = false
        }
        .task { await state.startIfNeeded() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("ABC Sheet Music", systemImage: "music.note.list")
                .font(.headline)
                .foregroundStyle(.primary)

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

            Button("Gen Coker") {
                Task { await state.generateCoker() }
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
            .keyboardShortcut(" ", modifiers: [])
            .help(state.audioSupported
                  ? "Play (concert pitch · downloads soundfont on first play)"
                  : "Web Audio unavailable in WebView")

            Button("Render") {
                Task { await state.renderNow() }
            }
            .keyboardShortcut(.return, modifiers: .command)

            Toggle("Live", isOn: $state.liveRender)

            Picker("Layout", selection: $state.measuresPerLine) {
                Text("1 / line").tag(1)
                Text("2 / line").tag(2)
                Text("4 / line").tag(4)
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .onChange(of: state.measuresPerLine) { _ in
                Task { await state.renderNow() }
            }

            Spacer()

            Button { state.openABC() } label: { Image(systemName: "folder") }
            Button { state.saveABC() } label: { Image(systemName: "square.and.arrow.down") }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ABC NOTATION")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(state.instrument.transposeSteps == 0 ? "Concert" : "Written · \(state.instrument.shortName)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            TextEditor(text: $state.abcText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .onChange(of: state.abcText) { _ in
                    state.isCokerTune = state.abcText.contains("Coker Pattern")
                    state.scheduleRender()
                }

            if !state.warnings.isEmpty {
                Divider()
                ScrollView {
                    Text(state.warnings.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 90)
                .background(Color.red.opacity(0.06))
            }
        }
    }

    private var statusBar: some View {
        HStack {
            Text("abcjs \(state.bridgeSignature)")
                .font(.caption)
                .foregroundStyle(.secondary)
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