"""Independent parser for the test adapter's fixed context/arena record."""
import hashlib
import struct
import subprocess
import sys

artifact, mode, source = sys.argv[1:]
result = subprocess.run([artifact], capture_output=True, timeout=45)
assert result.returncode == 0, (result.returncode, result.stderr[:200])
assert result.stdout == b"true\n", result.stdout
record = result.stderr
assert len(record) >= 208
words = struct.unpack_from("<26Q", record)
root, arena, page, value = words[:4]
allocs, allocated, collections, reclaimed, freed, mapped, reused = words[4:11]
assert root == 0 and value == 1 and page > 0
cursor = 208
blocks = []
arenas = []
while arena:
    nxt, size, first, reserved = struct.unpack_from("<4Q", record, cursor)
    assert first == 32 and reserved == 0 and size % page == 0
    assert cursor + size <= len(record)
    offset = 32
    previous_free = False
    while offset < size:
        physical, flags, length, scalars = struct.unpack_from("<4Q", record, cursor + offset)
        assert physical >= 32 and physical % 8 == 0 and offset + physical <= size
        assert flags in (0, 1), flags
        if mode == "reclamation":
            assert not (previous_free and flags == 0), "uncoalesced free neighbors"
            if flags:
                assert length <= physical - 32
                payload = record[cursor + offset + 32:cursor + offset + 32 + length]
                assert len(payload.decode("utf-8")) == scalars
        blocks.append((arena + offset, physical, flags))
        previous_free = flags == 0
        offset += physical
    assert offset == size
    arenas.append((arena, size))
    cursor += size
    arena = nxt
assert cursor == len(record)
assert mapped == sum(size for _, size in arenas)
if mode == "reclamation":
    assert allocs == 200002 and allocated > 64 * 65536
    assert mapped == 65536 and collections > 0 and reclaimed > 0 and freed > 0 and reused == 1
    watch, state, watch_size = words[11:14]
    trace = [words[14:17], words[17:20], words[20:23]]
    assert 0 < words[23] < 16384 and 0 < words[24] < 16384
    assert state == 3 and [entry[0] for entry in trace] == [1, 2, 3]
    assert all(entry[1] == watch for entry in trace)
    assert trace[0][2] == trace[1][2] == watch_size
    assert 0 < trace[2][2] <= watch_size
    assert any(start + 32 <= watch < start + size for start, size in arenas)
    # Swept marked block bytes and published frame/slot bytes are measured
    # separately. The terminal heap need not have been collected.
    assert b"\xe6\x97\xa5\xf0\x9f\x98\x80\0" in record[208:]
elif mode == "split40":
    assert [(b[1], b[2]) for b in blocks] == [(4024, 1), (40, 0)]
elif mode == "whole32":
    assert [(b[1], b[2]) for b in blocks] == [(4064, 1)]
elif mode == "coalesce":
    assert mapped == 4096 and reclaimed == 2
    assert [(b[1], b[2]) for b in blocks] == [(1800, 1), (200, 0), (2000, 1), (64, 0)]
elif mode == "growth":
    assert [size for _, size in arenas] == [4096, 12288]
    assert [(b[1], b[2]) for b in blocks] == [(3032, 1), (1032, 0), (9032, 1), (3224, 0)]
else:
    raise AssertionError(mode)
print(f"NATIVE_GC_OK mode={mode} allocations={allocs} bytes={allocated} collections={collections} "
      f"reclaimed={reclaimed} reclaimed_bytes={freed} observed_reuses={reused} mapped={mapped} "
      f"peak_live={words[23]} peak_roots={words[24]} arena_headers={32 * len(arenas)} "
      f"source={hashlib.sha256(open(source, 'rb').read()).hexdigest() if mode == 'reclamation' else 'raw-fixture'} "
      f"artifact={hashlib.sha256(open(artifact, 'rb').read()).hexdigest()}")
