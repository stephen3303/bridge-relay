import SwiftUI
import Security
import AVFoundation

/// Settings, opened from the main screen's gear: account, connection, glasses, voice, Bridge Pro, about.
struct SettingsView: View {
    @EnvironmentObject var glasses: GlassesController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var store = Store.shared
    @AppStorage("relayURL") private var relayURL = ""
    @State private var url = Relay.shared.isDemo || Relay.shared.isCloud ? "" : Relay.shared.baseURL
    @State private var token = Relay.shared.token
    @State private var testResult = ""
    @State private var photoResult = ""
    @State private var readBack = Conversation.readBack
    // A deleted voice falls back to the best installed one; show that rather than a blank picker.
    @State private var voiceID = Conversation.voices.contains { $0.identifier == Conversation.voiceID } ? Conversation.voiceID : ""
    @State private var hiFi = Conversation.hiFiSpeech
    @State private var natural = Conversation.naturalVoice
    @State private var previewer = AVSpeechSynthesizer()

    private enum Mode: String { case cloud, pc, demo }
    private var mode: Binding<Mode> {
        Binding {
            switch relayURL {
            case Relay.cloudAddress: return .cloud
            case Relay.demoAddress: return .demo
            default: return .pc
            }
        } set: { m in
            switch m {
            case .cloud: relayURL = Relay.cloudAddress
            case .demo: relayURL = Relay.demoAddress
            case .pc: relayURL = Relay.pcAddress(url) ?? ""
            }
            testResult = ""
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                connectionSection
                glassesSection
                Section {
                    Toggle("Read back what I said", isOn: $readBack)
                        .onChange(of: readBack) { _, on in Conversation.readBack = on }
                    Picker("Phone voice", selection: $voiceID) {
                        Text("Best installed").tag("")
                        ForEach(Conversation.voices, id: \.identifier) { Text(Conversation.label($0)).tag($0.identifier) }
                    }
                    .onChange(of: voiceID) { _, id in
                        Conversation.voiceID = id
                        preview()
                    }
                    if mode.wrappedValue != .demo {
                        Toggle("Natural voice", isOn: $natural)
                            // Saved only when it differs from the current value, so the refresh below isn't saved as a choice.
                            .onChange(of: natural) { _, on in if on != Conversation.naturalVoice { Conversation.naturalVoice = on } }
                            // An upgraded Pro install's default depends on Pro, which StoreKit reports after launch.
                            .onChange(of: store.isPro) { _, _ in natural = Conversation.naturalVoice }
                    }
                    Toggle("High-quality speech", isOn: $hiFi)
                        .onChange(of: hiFi) { _, on in Conversation.hiFiSpeech = on }
                } header: { Text("Voice") } footer: {
                    Text((readBack
                          ? "Bridge reads your message back and asks \"Ready to send it?\" Nothing is sent until you say yes."
                          : "Bridge sends what you say after a 2-second pause, without repeating it.")
                         + " The phone voice speaks unless the natural voice is on and available; download Premium voices in iPhone Settings > Accessibility > Spoken Content > Voices."
                         + (mode.wrappedValue == .pc ? " Natural voice sends each reply's text to OpenAI to be spoken, and needs an OpenAI key on the relay."
                            : mode.wrappedValue == .cloud ? " Natural voice is spoken by Amazon Polly and needs Bridge Pro." : "")
                         + " High-quality speech plays replies over the glasses' music link, which sounds much better, but each reply starts and listening resumes about a second later.")
                }
                Section("About") {
                    Link("Privacy policy", destination: Store.privacyURL)
                    Link("Terms of use", destination: Store.termsURL)
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }


    // MARK: connection

    private var connectionSection: some View {
        Section {
            Picker("Connect to", selection: mode) {
                Text("My PC").tag(Mode.pc)
                Text("Demo").tag(Mode.demo)
            }
            switch mode.wrappedValue {
            case .pc:
                TextField("https://your-pc.your-tailnet.ts.net", text: $url)
                    .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                SecureField("VOICE_TOKEN from the relay's .env", text: $token)
                Button("Save and test") { saveAndTest() }
            case .cloud:
                Button("Test") { test() }
            case .demo:
                EmptyView()
            }
            if !testResult.isEmpty { Text(testResult).font(.footnote) }
        } header: { Text("Connection") } footer: {
            switch mode.wrappedValue {
            case .pc: Text("Your PC runs the relay. See Help for setting it up.")
            case .cloud: Text("Your agents run on Bridge Cloud.")
            case .demo: Text("Sample replies, so you can try Bridge without a PC.")
            }
        }
    }

    private func saveAndTest() {
        guard let address = Relay.pcAddress(url) else { testResult = Relay.Failure.badAddress.localizedDescription; return }
        url = address
        relayURL = address
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = Keychain.write("relayToken", token)
        guard status == errSecSuccess else { testResult = Relay.Failure.keychain(status).localizedDescription; return }
        test()
    }

    private func test() {
        testResult = "Testing…"
        Task {
            do { _ = try await Relay.shared.inbox(after: nil, wait: false); testResult = "✓ Connected" }
            catch { testResult = error.localizedDescription }
        }
    }

    /// Not during a conversation: the recognizer would hear the sample and send it as a turn.
    private func preview() {
        previewer.stopSpeaking(at: .immediate)
        guard glasses.conversation.phase == .idle else { return }
        // The default session follows the silent switch, and a finished conversation's one plays from the earpiece.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: "This is how Bridge will sound.")
        u.voice = Conversation.bestVoice()
        u.rate = 0.5
        previewer.speak(u)
        // Hand the audio back (music the preview paused resumes) once it's done, unless a conversation started.
        Task {
            repeat { try? await Task.sleep(for: .milliseconds(300)) } while previewer.isSpeaking
            if glasses.conversation.phase == .idle { try? session.setActive(false, options: .notifyOthersOnDeactivation) }
        }
    }

    // MARK: glasses

    private var glassesSection: some View {
        Section("Glasses") {
            LabeledContent("Meta AI", value: glasses.registration)
            LabeledContent("Connected glasses", value: "\(glasses.deviceCount)")
            Button("Connect to Meta AI") { Task { await glasses.register() } }
            if glasses.cameraAllowed {
                Button("Test photo") {
                    guard store.isPro else { photoResult = "Photos need Bridge Pro."; return }
                    photoResult = "Taking a picture…"
                    Task {
                        do {
                            let jpeg = try await glasses.capturePhoto()
                            photoResult = try await Relay.shared.photo(jpeg, said: "What am I looking at?")
                        } catch { photoResult = error.localizedDescription }
                    }
                }
            } else {
                Button("Allow camera") { Task { await glasses.allowCamera() } }
            }
            if !photoResult.isEmpty { Text(photoResult).font(.footnote) }
        }
    }

}

