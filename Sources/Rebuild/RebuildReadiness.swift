enum RebuildPhase: Equatable {
    case idle, starting, recording, transcribing, completed, failed

    var isBusy: Bool { self == .starting || self == .recording || self == .transcribing }
}

struct RebuildReadiness: Equatable {
    var microphoneGranted = false
    var modelInstalled = false
    var runtimeReady = false
    var checking = true
    var modelVerificationFailed = false
    /// Access was refused or is blocked by policy, so only System Settings can
    /// grant it; asking again shows no prompt.
    var microphoneDenied = false
    var ready: Bool { !checking && microphoneGranted && modelInstalled && runtimeReady && !modelVerificationFailed }
    var nextStep: String {
        if checking { return "Checking your recording setup" }
        if microphoneDenied { return "Turn on microphone access in System Settings" }
        if !microphoneGranted { return "Allow microphone access" }
        if !runtimeReady { return "Install the local runtime" }
        if !modelInstalled { return "Install your voice model" }
        if modelVerificationFailed { return "Repair or verify your voice model" }
        return "Ready to record"
    }
}
