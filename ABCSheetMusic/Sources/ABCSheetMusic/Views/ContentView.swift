import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()
    @State private var editorText = ABCUtilities.defaultTestABC
    @State private var editorScrollRef: NSScrollView?

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
            Task { await updateScore() }
        }
        .onChange(of: state.editorRevision) { _ in
            editorText = state.programmaticEditorText
            if let tv = editorScrollRef?.documentView as? NSTextView {
                tv.string = state.programmaticEditorText
            }
        }
        .onChange(of: state.liveRender) { enabled in
            if enabled { Task { await updateScore() } }
        }
        .task {
            guard !CommandLine.arguments.contains("--self-test") else { return }
            await state.startIfNeeded()
        }
    }

    private func liveEditorText() -> String {
        ABCEditorView.currentText(in: editorScrollRef) ?? editorText
    }

    private func updateScore() async {
        await state.renderNow(concertABC: liveEditorText())
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("ABC Sheet Music", systemImage: "music.note.list")
                .font(.headline)

            Divider().frame(height: 22)

            Picker("Instrument", selection: $state.instrument) {
                ForEach(Instrument.allCases) { inst in
                    Text(inst.menuTitle).tag(inst)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 240)
            .onChange(of: state.instrument) { _ in
                Task { await state.instrumentChanged(concertABC: liveEditorText()) }
            }

            Button("12 Keys") {
                Task { await state.generate12Keys(from: liveEditorText()) }
            }
            .help("Add missing chromatic keys using your first bar — keeps clean key signatures")

            Divider().frame(height: 22)

            Button {
                Task {
                    if state.isPlaying { await state.stop() }
                    else { await state.play(concertABC: liveEditorText()) }
                }
            } label: {
                Label(state.isPlaying ? "Stop" : "Play", systemImage: state.isPlaying ? "stop.fill" : "play.fill")
            }
            .disabled(state.bridge == nil)

            Button("Update Score") {
                Task { await updateScore() }
            }
            .keyboardShortcut(.return, modifiers: .command)

            Toggle(isOn: $state.liveRender) {
                Text("Auto-update")
            }
            .help("When ON: score refreshes ~¼ sec after you stop typing. When OFF: use Update Score.")

            Picker("Layout", selection: $state.measuresPerLine) {
                Text("1 / line").tag(1)
                Text("2 / line").tag(2)
                Text("4 / line").tag(4)
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .onChange(of: state.measuresPerLine) { _ in
                Task { await updateScore() }
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
                Text("Concert pitch")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Text("Concert ABC here · score + sound use \(state.instrument.shortName) written pitch")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            ZStack(alignment: .topLeading) {
                ABCEditorView(text: $editorText, scrollRef: $editorScrollRef) { text in
                    state.userEdited(concertABC: text)
                }
                .id("abc-editor")
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
            Text(state.liveRender ? "· Auto-update ON" : "· Auto-update OFF — press Update Score")
                .font(.caption)
                .foregroundStyle(state.liveRender ? .green : .orange)
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