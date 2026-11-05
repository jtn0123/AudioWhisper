extension RebuildSession {
    func startDiagnostics(_ entry: DiagnosticEntry) {
        guard let config = configuration, let id = sessionID else { return }
        diagnosticTrace = diagnosticController?.start(config, id: id, entry: entry, mode: effectiveMode?.id)
        guard DiagnosticController.detailed, let trace = diagnosticTrace else { return }
        diagnosticSampling = Task { [weak trace] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard !Task.isCancelled, let trace else { return }
                trace.sample()
            }
        }
    }

    func finishDiagnostics(_ outcome: DiagnosticOutcome) {
        diagnosticSampling?.cancel()
        diagnosticSampling = nil
        if let milliseconds = timing.deliveryMilliseconds {
            diagnosticTrace?.duration(.stopToDelivery, milliseconds: milliseconds)
        }
        let delivery: DiagnosticDelivery
        switch deliveryStatus {
        case .copied: delivery = .copied
        case .pasted: delivery = .pasted
        case .unverified: delivery = .unverified
        case .manual: delivery = .manual
        default: delivery = .none
        }
        diagnosticController?.finish(diagnosticTrace, outcome: outcome, delivery: delivery)
        diagnosticTrace = nil
        microphoneDiagnostic = nil
    }
}
