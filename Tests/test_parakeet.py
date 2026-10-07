"""Bound long-file inference before creating an attention tensor."""
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Sources"))
from ml import parakeet


class ParakeetChunkTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "input.raw"
        self.reads = []
        self.generated = []
        self.merges = []
        self.tokens = []
        self.model = SimpleNamespace(
            preprocessor_config=SimpleNamespace(sample_rate=1, hop_length=1),
            generate=self.generate,
        )
        self.alignment = SimpleNamespace(
            merge_longest_contiguous=self.merge,
            merge_longest_common_subsequence=self.merge,
            tokens_to_sentences=lambda tokens, config: tokens,
            sentences_to_result=lambda tokens: SimpleNamespace(text=" ".join(token.text for token in tokens)),
        )
        modules = {
            "numpy": SimpleNamespace(float32="float32", fromfile=self.read),
            "mlx.core": SimpleNamespace(array=lambda samples: samples),
            "mlx": SimpleNamespace(),
            "parakeet_mlx.audio": SimpleNamespace(get_logmel=lambda samples, config: samples),
            "parakeet_mlx": SimpleNamespace(DecodingConfig=lambda: SimpleNamespace(sentence=None)),
            "parakeet_mlx.alignment": self.alignment,
        }
        modules["mlx"] = SimpleNamespace(core=modules["mlx.core"])
        self.addCleanup(mock.patch.stopall)
        mock.patch.dict(sys.modules, modules).start()
        mock.patch.object(parakeet, "load_parakeet_model", return_value=self.model).start()

    def fixture(self, frames):
        self.path.write_bytes(struct.pack(f"<{frames}f", *range(frames)))

    def read(self, path, dtype, count=-1, offset=0):
        self.reads.append((count, offset))
        with open(path, "rb") as file:
            file.seek(offset)
            data = file.read(count * 4 if count >= 0 else -1)
        return list(struct.unpack(f"<{len(data) // 4}f", data))

    def generate(self, samples):
        if len(samples) > 120:
            raise MemoryError("unbounded attention allocation")
        self.generated.append(samples)
        token = SimpleNamespace(text=f"chunk{len(self.generated)}", start=1, duration=1, end=2)
        self.tokens.append(token)
        return [SimpleNamespace(text="short speech", tokens=[token])]

    def merge(self, previous, current, overlap_duration):
        self.merges.append(overlap_duration)
        return previous + current

    def test_short_file_retains_one_generation_and_text(self):
        self.fixture(12)
        self.assertEqual(parakeet.transcribe("repo", str(self.path)), {"success": True, "text": "short speech"})
        self.assertEqual(len(self.generated), 1)
        self.assertEqual(self.reads, [(120, 0)])

    def test_long_file_bounds_reads_and_inference_and_keeps_tail(self):
        self.fixture(330)
        result = parakeet.transcribe("repo", str(self.path))
        self.assertEqual(result["text"], "chunk1 chunk2 chunk3 chunk4")
        self.assertEqual(self.reads, [(120, start * 4) for start in (0, 105, 210, 315)])
        self.assertEqual([len(samples) for samples in self.generated], [120, 120, 120, 15])
        self.assertEqual([token.start for token in self.tokens], [1, 106, 211, 316])
        self.assertEqual(self.merges, [15, 15, 15])

    def test_alignment_fallback_preserves_chunks(self):
        self.fixture(130)
        self.alignment.merge_longest_contiguous = mock.Mock(side_effect=RuntimeError("no contiguous overlap"))
        self.assertEqual(parakeet.transcribe("repo", str(self.path))["text"], "chunk1 chunk2")
        self.assertEqual(self.merges, [15])

    def test_missing_file_is_rejected_before_model_load(self):
        with self.assertRaises(FileNotFoundError):
            parakeet.transcribe("repo", str(self.path))
        self.assertEqual(self.generated, [])


if __name__ == "__main__":
    unittest.main()
