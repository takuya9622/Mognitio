"""Run the versioned source catalog through CLI run/build and native execution.

The catalog stores JSON-compatible quoted strings in a Lisp data list. This
reader accepts only the two documented row forms and does not evaluate Lisp.
Results contain byte streams as hex and no temporary or machine-specific paths.
"""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]


def catalog():
    group = None
    number = 0
    for line in (ROOT / "tests/v08-conformance.lisp").read_text().splitlines():
        match = re.fullmatch(r'    \("(C08-\d{2})"', line)
        if match:
            group, number = match[1], 0
        elif line.startswith('     ("'):
            text = line.strip()[1:]
            source, end = json.JSONDecoder().raw_decode(text)
            expected, end = json.JSONDecoder().raw_decode(text[end:].lstrip())
            number += 1
            yield f"{group}.{number:02d}", source, expected


def invoke(args):
    result = subprocess.run(args, capture_output=True, timeout=30)
    return result.returncode, result.stdout, result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    args = parser.parse_args()
    rows = []
    manifest = json.loads((ROOT / "verification/v0.8.1-cases.json").read_text())["fixtures"]
    with tempfile.TemporaryDirectory(prefix="mognitio-v08-") as directory:
        source_path = pathlib.Path(directory) / "case.mgn"
        artifact = pathlib.Path(directory) / "program"
        for index, (case_id, source, expected) in enumerate(catalog()):
            source_path.write_bytes(source.encode("utf-8"))
            row = {"id": case_id, "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(), "expected": expected}
            assert row == manifest[index], case_id
            run = invoke([str(ROOT / "bin/mgn"), "run", str(source_path)])
            artifact.write_bytes(b"previous")
            build = invoke([str(ROOT / "bin/mgn"), "build", "--target", "linux/amd64", "--output", str(artifact), str(source_path)])
            if expected in ("parse", "semantic", "reject"):
                phase = "parse" if b": parse:" in run[2] else "semantic"
                assert expected == "reject" or phase == expected, (case_id, run)
                for result in (run, build):
                    assert result[0] == 1 and result[1] == b"" and f": {phase}:".encode() in result[2], (case_id, result)
                assert artifact.read_bytes() == b"previous", case_id
                row.update(run_status=1, build_status=1, phase=phase, stdout_hex="", output_preserved=True)
            else:
                expected_status = 4 if expected.startswith("failure:") else 0
                expected_out = b"" if expected_status else (expected + "\n").encode()
                expected_err = ("runtime: " + expected[8:] + "\n").encode() if expected_status else b""
                assert run == (expected_status, expected_out, expected_err), (case_id, run)
                assert build == (0, b"", b""), (case_id, build)
                native = invoke([str(artifact)])
                assert native == run, (case_id, native, run)
                image = artifact.read_bytes()
                assert invoke([str(ROOT / "bin/mgn"), "build", "--target", "linux/amd64", "--output", str(artifact), str(source_path)]) == (0, b"", b"")
                assert artifact.read_bytes() == image, case_id
                row.update(run_status=run[0], build_status=0, native_status=native[0], stdout_hex=run[1].hex(), stderr_hex=run[2].hex(),
                           artifact_sha256=hashlib.sha256(image).hexdigest(), deterministic=True)
            rows.append(row)
    assert len(rows) == len(manifest)
    report = {"implementation_head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
              "commands": ["bin/mgn run SOURCE", "bin/mgn build --target linux/amd64 --output ARTIFACT SOURCE", "ARTIFACT"],
              "acceptance_ids": len({row["id"].split(".")[0] for row in rows}), "fixtures": rows}
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Acceptance IDs={report['acceptance_ids']} Fixtures={len(rows)} Failures=0")


if __name__ == "__main__":
    main()
