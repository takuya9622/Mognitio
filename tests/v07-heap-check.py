"""Read instrumented heap blocks and static descriptors independently of Lisp."""
import hashlib
import struct
import subprocess
import sys

image = open(sys.argv[1], "rb").read()
result = subprocess.run([sys.argv[1]], capture_output=True, timeout=45)
assert result.returncode == 0, (result.returncode, result.stderr[:100])
assert result.stdout == b"true\n"
record = result.stderr
words = struct.unpack_from("<26Q", record)
root, arena, page, value = words[:4]
allocs, allocated, collections, reclaimed, freed, mapped, reused = words[4:11]
assert root == 0 and value == 1
assert allocs > 8000 and allocated > 60 * 4096
assert mapped == 4096 and collections > 0 and reclaimed > 0 and freed > 0 and reused == 1
assert 0 < words[23] < 2048 and 0 < words[24] < 2048
assert words[12] == 3
trace = [words[14:17], words[17:20], words[20:23]]
assert [t[0] for t in trace] == [1, 2, 3] and all(t[1] == words[11] for t in trace)
assert trace[0][2] == trace[1][2] == words[13] and 0 < trace[2][2] <= words[13]
phoff = struct.unpack_from("<Q", image, 32)[0]
file_start, virtual_start, _, file_size = struct.unpack_from("<4Q", image, phoff + 8)
def static(address, count):
    offset = address - virtual_start + file_start
    assert 0 <= offset <= len(image) - count * 8
    return struct.unpack_from("<" + "Q" * count, image, offset)

cursor = 208
blocks = {}
texts = {}
kinds = set()
while arena:
    nxt, size, first, reserved = struct.unpack_from("<4Q", record, cursor)
    assert first == 32 and reserved == 0 and size % page == 0
    offset = 32
    previous_free = False
    while offset < size:
        physical, flags, metadata, tag = struct.unpack_from("<4Q", record, cursor + offset)
        assert physical >= 32 and physical % 8 == 0 and offset + physical <= size
        assert flags in (0, 1, 17, 33, 49), flags
        assert not (previous_free and flags == 0)
        if flags:
            kind = flags >> 4
            kinds.add(kind)
            if kind == 0:
                assert metadata <= physical - 32
                text = record[cursor + offset + 32:cursor + offset + 32 + metadata]
                assert len(text.decode("utf-8")) == tag
                blocks[arena + offset] = (kind, None, ())
                texts[arena + offset] = text
            else:
                dk, type_id, variant, slots, ref_count = static(metadata, 5)
                assert dk == kind and physical >= 32 + 8 * max(1, slots)
                refs = static(metadata + 40, ref_count)
                assert list(refs) == sorted(set(refs)) and all(i < slots for i in refs)
                if kind == 3:
                    concrete, contract, methods = static(tag, 3)
                    assert contract == type_id and slots == 1 and refs == (0,)
                    assert methods == 1 and static(tag + 24, 1)[0] > 0
                else:
                    assert tag == variant
                children = tuple(struct.unpack_from("<Q", record, cursor + offset + 32 + i * 8)[0] for i in refs)
                blocks[arena + offset] = (kind, type_id, children)
        previous_free = flags == 0
        offset += physical
    assert offset == size
    cursor += size
    arena = nxt
assert cursor == len(record) and {0, 1, 2, 3} <= kinds
# The retained interface is the only box in this fixture. Traverse its full
# graph, distinguishing shared child addresses, using only emitted metadata.
boxes = [address for address, entry in blocks.items() if entry[0] == 3]
assert len(boxes) == 1
seen = set()
pending = boxes[:]
while pending:
    address = pending.pop()
    if address in seen:
        continue
    seen.add(address)
    assert address in blocks, "reachable child is not an allocated object start"
    pending.extend(blocks[address][2])
assert len(seen) == 5, seen  # box -> enum -> pair -> shared leaf -> text
child_texts = {address for address, text in texts.items() if text == b"child!"}
assert len(child_texts) == 1
child_nodes = {address for address, entry in blocks.items() if entry[0] == 1 and entry[1] == 0 and entry[2] == tuple(child_texts)}
assert len(child_nodes) == 1
assert not any(entry[0] == 1 and entry[1] == 1 and child_nodes.intersection(entry[2]) for entry in blocks.values()), "dead parent was retained"
assert b"keep!" in record and b"child!" in record
print(f"VALUE_GC_OK allocations={allocs} bytes={allocated} collections={collections} reclaimed={reclaimed} reused={reused} mapped={mapped} reachable={len(seen)} peak_live={words[23]} peak_roots={words[24]} max_passes={words[25]} artifact={hashlib.sha256(image).hexdigest()}")
