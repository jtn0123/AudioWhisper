import AVFAudio

// Keeping the microphone ready between recordings (L11). The cold path in
// `startPreparedEngine` is unchanged; a held input only replaces the engine
// preparation and the tap.
extension AudioEngineRecorder {
    func configureWarmMicrophone() {
        warmMicrophone.chosenUID = { [weak self] in
            self?.microphoneChooser.choose(ranking: AppDefaults.microphoneRanking) ?? ""
        }
        warmMicrophone.recordingActive = { [weak self] in
            guard let self else { return false }
            return self.audioEngine != nil || self.hardwarePreparation.isInFlight
        }
    }

    /// Opens the microphone ahead of the first recording if the user asked
    /// for it, and follows sleep and default-input changes from then on.
    func startWarmMicrophone() {
        warmWatchers = warmMicrophone.watchSystem()
        warmMicrophone.refresh()
    }

    /// The held input, if it is still the one this recording would choose.
    func lendWarmInput() -> WarmMicrophone<PreparedAudioEngine>.Held? {
        guard warmMicrophone.isWarm else { return nil }
        return warmMicrophone.lend(for: microphoneChooser.choose(ranking: AppDefaults.microphoneRanking))
    }

    /// Feeds the capture from the held input, pre-roll first, or from a new tap.
    func connect(_ prepared: PreparedAudioEngine, lent: WarmMicrophone<PreparedAudioEngine>.Held?) {
        guard let lent else {
            prepared.inputNode.installTap(onBus: 0, bufferSize: 1024, format: prepared.format) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }
            return
        }
        attach(lent.feed)
    }

    func attach(_ feed: AudioFeed) {
        attachedFeed = feed
        feed.attach(captureSink())
    }

    /// Built outside the main actor: the feed calls it on the audio thread.
    nonisolated private func captureSink() -> (AVAudioPCMBuffer) -> Void {
        { [weak self] buffer in self?.processAudioBuffer(buffer) }
    }
}
