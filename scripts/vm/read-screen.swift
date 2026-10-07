// OCR of guest screenshots. No host desktop capture or host input events.
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("Usage: read-screen <guest-screenshot.png>\n", stderr)
    exit(1)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image).perform([request])
let rows: [[String: Any]] = (request.results ?? []).compactMap { observation in
    guard let text = observation.topCandidates(1).first?.string else { return nil }
    let bounds = observation.boundingBox
    return ["text": text, "x": Int(bounds.midX * Double(image.width)),
            "y": Int((1 - bounds.midY) * Double(image.height))]
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]))
