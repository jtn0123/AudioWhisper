These original, tiny sum/broadcast models exercise real Core ML compilation,
load validation, and rejection of incompatible encoder dimensions in ordinary CI.
They contain no downloaded weights and do not test speech recognition.

Run `python3 Tests/Resources/CoreMLFixtures/generate.py` to reproduce both models
using Python's standard library. The generator documents the Apple protobuf schemas.
The input uses the expected Base mel shape. One output has the expected Base
encoder shape; the other deliberately changes its final dimension to one.
Both sum all input elements and broadcast that scalar to the declared output,
keeping the input connected to the graph without any learned weights.
