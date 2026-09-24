"""Independently inspect generic Result/Box lifetime in an instrumented image."""
import struct
import subprocess
import sys

image = open(sys.argv[1], "rb").read()
result = subprocess.run([sys.argv[1]], capture_output=True, timeout=45)
assert result.returncode == 0 and result.stdout == b"true\n", (result.returncode, result.stdout)
data = result.stderr
words = struct.unpack_from("<26Q", data)
assert words[0] == 0 and words[3] == 1
assert words[4] > 4000 and words[6] > 0 and words[7] > 0 and words[10] == 1, words[:11]
assert words[9] == 4096
phoff = struct.unpack_from("<Q", image, 32)[0]
file_start, virtual_start = struct.unpack_from("<2Q", image, phoff + 8)


def static(address, count):
    offset = address - virtual_start + file_start
    assert 0 <= offset <= len(image) - count * 8
    return struct.unpack_from("<" + "Q" * count, image, offset)


arena, cursor = words[1], 208
objects, texts = {}, {}
while arena:
    nxt, size, first, reserved = struct.unpack_from("<4Q", data, cursor)
    assert first == 32 and reserved == 0
    offset = 32
    while offset < size:
        physical, flags, metadata, tag = struct.unpack_from("<4Q", data, cursor + offset)
        assert physical >= 32 and physical % 8 == 0 and offset + physical <= size
        assert flags in (0, 1, 17, 33)
        address = arena + offset
        if flags == 1:
            text = data[cursor + offset + 32:cursor + offset + 32 + metadata]
            assert len(text.decode("utf-8")) == tag
            texts[address] = text
        elif flags:
            kind, type_id, variant, slots, count = static(metadata, 5)
            refs = static(metadata + 40, count)
            assert kind == flags >> 4 and tag == variant and slots == 1
            assert refs == (0,), "generic reference payload mask missing"
            objects[address] = (kind, struct.unpack_from("<Q", data, cursor + offset + 32)[0])
        offset += physical
    cursor += size
    arena = nxt
assert cursor == len(data)
kept = {address for address, text in texts.items() if text == b"keep!"}
assert len(kept) == 1
boxes = {address for address, (kind, child) in objects.items() if kind == 1 and child in kept}
assert len(boxes) == 1
assert not any(kind == 2 and child in boxes for kind, child in objects.values()), "dead Result parent retained"
print(f"GENERIC_GC_OK allocations={words[4]} collections={words[6]} reclaimed={words[7]} reused={words[10]}")
