import Foundation

struct DictationModeArchive: Codable {
    static let maximumBytes = 8_388_608
    let schemaVersion: Int
    let modes: [SavedDictationMode]

    enum ArchiveError: String, LocalizedError {
        case invalid = "This mode file is invalid or uses an unsupported version."
        case oversized = "Mode files must be smaller than 8 MB."
        var errorDescription: String? { rawValue }
    }

    static func export(_ modes: [SavedDictationMode]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Self(schemaVersion: 1, modes: modes))
        guard data.count <= maximumBytes else { throw ArchiveError.oversized }
        return data
    }

    /// Validate everything before committing one write. Context consent belongs
    /// to this Mac and is deliberately reset when importing a mode.
    static func importing(_ data: Data, into existing: [SavedDictationMode]) throws -> [SavedDictationMode] {
        guard data.count <= maximumBytes else { throw ArchiveError.oversized }
        guard let archive = try? JSONDecoder().decode(Self.self, from: data), archive.schemaVersion == 1,
              !archive.modes.isEmpty else { throw ArchiveError.invalid }
        guard existing.count + archive.modes.count <= 32 else { throw SavedDictationMode.ValidationError.limit }
        var result = existing
        for mode in archive.modes {
            var settings = mode.settings
            guard settings.writing.instructions.count <= 4_000, settings.vocabulary.count <= 32_000,
                  !settings.cleanupModel.isEmpty, settings.cleanupModel.count <= 200 else { throw ArchiveError.invalid }
            settings.writing.contextSource = .none
            var name = mode.name
            var suffix = 1
            while result.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                name = String(mode.name.prefix(40)) + " (imported \(suffix))"
                suffix += 1
            }
            result.append(try SavedDictationMode.make(name: name, settings: settings, existing: result))
        }
        return result
    }
}

extension SavedDictationMode {
    func updated(name: String, settings: DictationModeSettings, existing: [Self]) throws -> Self {
        let validated = try Self.make(name: name, settings: settings, existing: existing.filter { $0.id != id })
        return Self(id: id, name: validated.name, settings: validated.settings)
    }
}
