"""Measure fixed-point passes for a finite forty-level shared type graph."""
import struct
import subprocess
import sys
import time

start = time.perf_counter()
result = subprocess.run([sys.argv[1]], capture_output=True, timeout=45)
elapsed = time.perf_counter() - start
assert result.returncode == 0 and result.stdout == b"true\n"
words = struct.unpack_from("<26Q", result.stderr)
assert words[0] == 0 and words[3] == 1
assert words[9] == 4096 and words[25] == 43
assert words[7] > 0 and words[23] < 4096
print(f"VALUE_DEPTH_OK levels=40 max_passes={words[25]} collections={words[6]} peak_live={words[23]} mapped={words[9]} elapsed_seconds={elapsed:.6f}")
