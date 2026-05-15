import XCTest
@testable import AudioWhisper

// MARK: - Data Manager Performance Tests
@MainActor
final class DataManagerPerformanceTests: XCTestCase {

    func testTranscriptionRecordCreationPerformance() {
        measure {
            for index in 0..<1000 {
                let record = TranscriptionRecord(
                    text: "Test transcription text \(index)",
                    provider: .local,
                    duration: Double(index) * 0.5
                )
                _ = record
            }
        }
    }
}

// MARK: - Model Performance Tests
final class ModelPerformanceTests: XCTestCase {

    func testTranscriptionProviderAllCasesPerformance() {
        measure {
            for _ in 0..<10000 {
                for provider in TranscriptionProvider.allCases {
                    _ = provider.displayName
                }
            }
        }
    }

    func testWhisperModelAllCasesPerformance() {
        measure {
            for _ in 0..<10000 {
                for model in WhisperModel.allCases {
                    _ = model.displayName
                    _ = model.estimatedSize
                }
            }
        }
    }
}

// MARK: - Color Theme Performance Tests
final class ColorThemePerformanceTests: XCTestCase {

    func testColorThemeGradientColorsPerformance() {
        measure {
            for _ in 0..<1000 {
                for theme in ColorTheme.allCases {
                    _ = theme.gradientColors
                }
            }
        }
    }

    func testVisualIntensityPropertiesPerformance() {
        measure {
            for _ in 0..<1000 {
                for intensity in VisualIntensity.allCases {
                    _ = intensity.glowIntensity
                    _ = intensity.particleMultiplier
                    _ = intensity.confettiCount
                    _ = intensity.spring
                }
            }
        }
    }
}

// MARK: - String Processing Performance Tests
final class StringProcessingPerformanceTests: XCTestCase {

    func testHexColorParsingPerformance() {
        let hexColors = ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF", "#000000"]

        measure {
            for _ in 0..<1000 {
                for hex in hexColors {
                    _ = Color(hex: hex)
                }
            }
        }
    }
}

// MARK: - Layout Metrics Performance Tests
final class LayoutMetricsPerformanceTests: XCTestCase {

    func testLayoutMetricsAccessPerformance() {
        measure {
            for _ in 0..<10000 {
                _ = LayoutMetrics.RecordingWindow.size
                _ = LayoutMetrics.RecordingWindow.cornerRadius
                _ = LayoutMetrics.DashboardWindow.initialSize
                _ = LayoutMetrics.DashboardWindow.minimumSize
                _ = LayoutMetrics.DashboardWindow.sidebarWidth
                _ = LayoutMetrics.TranscriptionHistory.minimumSize
                _ = LayoutMetrics.Welcome.windowSize
            }
        }
    }
}

// MARK: - Localized Strings Performance Tests
final class LocalizedStringsPerformanceTests: XCTestCase {

    func testLocalizedStringsAccessPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = LocalizedStrings.UI.ready
                _ = LocalizedStrings.UI.recording
                _ = LocalizedStrings.UI.processing
                _ = LocalizedStrings.UI.success
                _ = LocalizedStrings.Alerts.errorTitle
                _ = LocalizedStrings.Menu.record
                _ = LocalizedStrings.Menu.settings
            }
        }
    }
}

// MARK: - Encoding Performance Tests
final class EncodingPerformanceTests: XCTestCase {

    func testColorThemeCodablePerformance() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        measure {
            for theme in ColorTheme.allCases {
                do {
                    let data = try encoder.encode(theme)
                    _ = try decoder.decode(ColorTheme.self, from: data)
                } catch {
                    XCTFail("Encoding/decoding failed")
                }
            }
        }
    }

    func testVisualIntensityCodablePerformance() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        measure {
            for intensity in VisualIntensity.allCases {
                do {
                    let data = try encoder.encode(intensity)
                    _ = try decoder.decode(VisualIntensity.self, from: data)
                } catch {
                    XCTFail("Encoding/decoding failed")
                }
            }
        }
    }
}

import SwiftUI
