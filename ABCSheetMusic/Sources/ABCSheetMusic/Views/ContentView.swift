import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    /// Local editor text — isolated from score render updates so typing is never interrupted.
    @State private var editorText = ABCUtilities.defaultTestABC

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                editorPane
                    .frame(minWidth: 300, idealWidth: 380, maxWidth: 560)
                Group {
                    if let bridge = state.bridge {
                        ScoreWebView(bridge: bridge)
                    } else {
                        ProgressView("Loading abcjs…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 400)
            }
            Divider()
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(NotificationCenter.default.publisher(for: .abcPlaybackFinished)) { _ in
            state.isPlaying = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .generate12Keys)) { _ in
            Task { await state.generate12Keys(from: editorText) }
        }
        .onChange(of: state.editorRevision) { _ in
            editorText = state.programmaticEditorText
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
                Task { await state.instrumentChanged(concertABC: editorText) }
            }

            Button("12 Keys") {
                Task { await state.generate12Keys(from: editorText) }
            }
            .help("Expand your one-bar pattern through all 12 chromatic keys (book style)")

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
            .keyboardShortcut(" ", modifiers: [])
            .help("Play at concert pitch (soundfont downloads on first play)")

            if !state.liveRender {
                Button("Update Score") {
                    Task { await state.renderNow(concertABC: editorText) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("Redraw the score now — only needed when Live is off")
            }

            Toggle("Live", isOn: $state.liveRender)
                .help("Auto-update the score as you type")

            Picker("Layout", selection: $state.measuresPerLine) {
                Text("1 / line").tag(1)
                Text("2 / line").tag(2)
                Text("4 / line").tag(4)
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .onChange(of: state.measuresPerLine) { _ in
                Task { await state.renderNow(concertABC: editorText) }
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
                Text("Concert pitch · edit here")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Text(state.isTwelveKeys
                 ? "12 Keys on score · edit your one-bar concert pattern here"
                 : "Score shows \(state.instrument.shortName) written pitch · edit concert ABC here")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            ZStack(alignment: .topLeading) {
                ABCEditorView(text: $editorText) { text in
                    state.userEdited(concertABC: text)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if state.isBootstrapping {
                    Color(nsColor: .textBackgroundColor).opacity(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 240)

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