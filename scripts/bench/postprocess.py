"""Evaluate delivered text using Swift functions extracted from production source."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def build_helper(root: Path, base: Path) -> Path:
    guard_path = root / "Sources/Services/SemanticCorrectionService.swift"
    cleaner_path = root / "Sources/Services/SpeechToTextService.swift"
    guard = guard_path.read_text().split("    static func maxChangeRatio", 1)[1].rsplit("}", 1)[0]
    cleaner = cleaner_path.read_text().split("    private static let acousticMarkers", 1)[1].rsplit("}", 1)[0]
    source = (
        "import Foundation\n" + (root / "Sources/Services/CorrectionIntegrity.swift").read_text()
        + "\nenum Guard {\n    static func maxChangeRatio" + guard + "}\n"
        "enum Cleaner {\n    private static let acousticMarkers" + cleaner + "}\n"
        """
while let line = readLine() {
    let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let text = input["text"] as! String
    var output = input
    if input["kind"] as? String == "writing" {
        let original = input["input"] as! String
        let ratio = Guard.maxChangeRatio(for: input["category"] as! String)
        let delivered = Guard.safeMerge(original: original, corrected: text, maxChangeRatio: ratio)
        output["delivered"] = delivered
        output["guard_rejected"] = text != original && delivered == original
        output["edit_ratio"] = Guard.normalizedEditDistance(a: original, b: text)
        output["max_change_ratio"] = ratio
    } else {
        output["delivered"] = Cleaner.cleanTranscriptionText(text)
    }
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
"""
    )
    source_path = base / "ProductionTextEvaluation.swift"
    source_path.write_text(source)
    binary = base / "ProductionTextEvaluation"
    subprocess.run(["xcrun", "swiftc", "-O", str(source_path), "-o", str(binary)], check=True)
    (base / "production-text-source.json").write_text(json.dumps({
        str(path.relative_to(root)): hashlib.sha256(path.read_bytes()).hexdigest()
        for path in [guard_path, cleaner_path, root / "Sources/Services/CorrectionIntegrity.swift"]
    }, indent=2) + "\n")
    return binary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    binary = build_helper(root, args.base)
    for path in sorted((args.base / "results").glob("*.jsonl")):
        if ".partial-" in path.name or ".delivered." in path.name:
            continue
        rows = [json.loads(line) for line in path.read_text().splitlines()]
        text_rows = [row for row in rows if row["kind"] in ["quality", "writing"]]
        completed = any(row["kind"] == "complete" for row in rows)
        if not completed or not text_rows:
            continue
        payload = "".join(json.dumps(row) + "\n" for row in text_rows)
        result = subprocess.run([str(binary)], input=payload, text=True, capture_output=True, check=True)
        destination = path.with_suffix(".delivered.jsonl")
        destination.write_text(result.stdout)
        print("EVALUATED", path.name, len(text_rows))


if __name__ == "__main__":
    main()
