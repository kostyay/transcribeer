import SwiftUI

struct SettingsView: View {
    @Binding var config: AppConfig
    @State private var apiKey: String = ""
    @State private var modelCatalog = ModelCatalogService()

    var body: some View {
        TabView {
            Tab("Pipeline", systemImage: "bolt") {
                pipelineTab
            }
            Tab("Transcription", systemImage: "waveform") {
                transcriptionTab
            }
            Tab("Summarization", systemImage: "text.badge.checkmark") {
                summarizationTab
            }
        }
        .frame(width: 460, height: 360)
        .onAppear {
            apiKey = KeychainHelper.getAPIKey(backend: config.llmBackend) ?? ""
        }
    }

    // MARK: - Pipeline

    private var pipelineTab: some View {
        Form {
            Section {
                Toggle("Transcribe after recording", isOn: Binding(
                    get: { config.pipelineMode != "record-only" },
                    set: { enabled in
                        config.pipelineMode = enabled ? "record+transcribe" : "record-only"
                        save()
                    }
                ))

                Toggle("Summarize after transcription", isOn: Binding(
                    get: { config.pipelineMode == "record+transcribe+summarize" },
                    set: { enabled in
                        config.pipelineMode = enabled ? "record+transcribe+summarize" : "record+transcribe"
                        save()
                    }
                ))
                .disabled(config.pipelineMode == "record-only")
            } header: {
                Text("Pipeline Steps")
            }

            Section {
                Toggle("Auto-record Zoom meetings", isOn: Binding(
                    get: { config.zoomAutoRecord },
                    set: { config.zoomAutoRecord = $0; save() }
                ))
            } header: {
                Text("Zoom Integration")
            } footer: {
                Text("Start/stop recording automatically when a Zoom meeting starts/ends.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    // MARK: - Transcription

    private var transcriptionTab: some View {
        Form {
            Section {
                modelPicker
            } header: {
                HStack {
                    Text("Whisper model")
                    Spacer()
                    if modelCatalog.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button {
                            Task { await modelCatalog.refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh model list")
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Models are downloaded on first use (~0.1–1.5 GB). Stored in ~/.transcribeer/models/.")
                    if let message = modelCatalog.lastError {
                        Text(message).foregroundStyle(.orange)
                    }
                }
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Speaker detection", selection: Binding(
                    get: { config.diarization },
                    set: { config.diarization = $0; save() }
                )) {
                    Text("pyannote").tag("pyannote")
                    Text("none").tag("none")
                }
            } header: {
                Text("Diarization")
            } footer: {
                Text(config.diarization == "none"
                     ? "Disabled — transcript will have a single unlabelled speaker."
                     : "Detects and labels multiple speakers in the transcript.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .task {
            // Make sure whatever the user has selected is visible in the list,
            // then refresh from the network. If refresh fails the pre-seeded
            // entry keeps the UI usable.
            modelCatalog.ensureEntry(for: AppConfig.canonicalWhisperModel(config.whisperModel))
            await modelCatalog.refresh()
            modelCatalog.ensureEntry(for: AppConfig.canonicalWhisperModel(config.whisperModel))
        }
    }

    @ViewBuilder
    private var modelPicker: some View {
        let selected = AppConfig.canonicalWhisperModel(config.whisperModel)
        Picker("Model", selection: Binding(
            get: { selected },
            set: { config.whisperModel = $0; save() }
        )) {
            if modelCatalog.entries.isEmpty {
                Text(selected).tag(selected)
            } else {
                ForEach(modelCatalog.entries) { entry in
                    ModelPickerRow(entry: entry).tag(entry.id)
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(modelCatalog.entries.isEmpty)
    }

    // MARK: - Summarization

    private var summarizationTab: some View {
        Form {
            Section {
                Picker("Backend", selection: Binding(
                    get: { config.llmBackend },
                    set: { newBackend in
                        config.llmBackend = newBackend
                        apiKey = KeychainHelper.getAPIKey(backend: newBackend) ?? ""
                        save()
                    }
                )) {
                    Text("ollama").tag("ollama")
                    Text("openai").tag("openai")
                    Text("anthropic").tag("anthropic")
                }

                TextField("Model", text: Binding(
                    get: { config.llmModel },
                    set: { config.llmModel = $0 }
                ))
                .onSubmit { save() }

                if config.llmBackend == "ollama" {
                    TextField("Ollama host", text: Binding(
                        get: { config.ollamaHost },
                        set: { config.ollamaHost = $0 }
                    ))
                    .onSubmit { save() }
                }

                if config.llmBackend != "ollama" {
                    SecureField("API key", text: $apiKey)
                        .onSubmit {
                            if !apiKey.isEmpty {
                                KeychainHelper.setAPIKey(backend: config.llmBackend, key: apiKey)
                            }
                        }
                }
            } header: {
                Text("LLM Configuration")
            }

            Section {
                Toggle("Ask for prompt profile on stop", isOn: Binding(
                    get: { config.promptOnStop },
                    set: { config.promptOnStop = $0; save() }
                ))
            } header: {
                Text("Prompts")
            } footer: {
                Text("Show a profile picker when you stop a recording.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func save() {
        ConfigManager.save(config)
    }
}

/// One row in the Whisper model picker, rendering name + status badges.
///
/// Kept as its own view so the `Picker` can render it both as the collapsed
/// label and inside the menu without duplicating layout.
private struct ModelPickerRow: View {
    let entry: WhisperModelEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(entry.displayName)
            if entry.isRecommendedDefault {
                Text("default").modifier(BadgeStyle(tint: .accentColor))
            }
            if entry.isDownloaded {
                Text("downloaded").modifier(BadgeStyle(tint: .green))
            }
            if entry.isDisabled {
                Text("unsupported").modifier(BadgeStyle(tint: .secondary))
            }
        }
    }
}

private struct BadgeStyle: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
