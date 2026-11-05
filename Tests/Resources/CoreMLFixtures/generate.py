"""Reproduce tiny, original Core ML contract fixtures without extra packages.

Field numbers follow Apple's Model.proto, FeatureTypes.proto and
NeuralNetwork.proto: https://github.com/apple/coremltools/tree/main/mlmodel/format
These sum/broadcast models exercise compilation/shape validation, not recognition.
"""

from pathlib import Path


def varint(value: int) -> bytes:
    result = bytearray()
    while value > 127:
        result.append((value & 127) | 128)
        value >>= 7
    result.append(value)
    return bytes(result)


def integer(field: int, value: int) -> bytes:
    return varint(field << 3) + varint(value)


def message(field: int, value: bytes) -> bytes:
    return varint((field << 3) | 2) + varint(len(value)) + value


def string(field: int, value: str) -> bytes:
    return message(field, value.encode())


def feature(name: str, shape: list[int]) -> bytes:
    array = message(1, b"".join(varint(size) for size in shape)) + integer(2, 65568)
    return string(1, name) + message(3, message(5, array))


def model(output_shape: list[int]) -> bytes:
    description = message(1, feature("melspectrogram_features", [1, 80, 1, 3000]))
    description += message(10, feature("encoder_output_embeds", output_shape))
    reduce = string(1, "sum") + string(2, "melspectrogram_features") + string(3, "scalar")
    reduce += message(1270, integer(2, 1) + integer(3, 1))  # Keep dimensions; reduce all axes.
    broadcast = string(1, "broadcast") + string(2, "scalar") + string(3, "encoder_output_embeds")
    broadcast += message(1105, message(1, b"".join(varint(size) for size in output_shape)))
    network = message(1, reduce) + message(1, broadcast) + integer(5, 1)
    return integer(1, 4) + message(2, description) + message(500, network)


if __name__ == "__main__":
    directory = Path(__file__).parent
    (directory / "encoder-shape.mlmodel").write_bytes(model([1, 512, 1, 1500]))
    (directory / "wrong-shape.mlmodel").write_bytes(model([1, 512, 1, 1]))
