#!/usr/bin/env python3
"""Generate H06 per-rule scanner eligibility, bypass and replay reports."""

from __future__ import annotations

import csv
import hashlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

REASONS = [
    "none",
    "tree",
    "innerRecords",
    "invalidTable",
    "state",
    "position",
    "steps",
    "trace",
    "depth",
    "budgetEdge",
    "failureDiagnostic",
    "primitiveScan",
    "recordLowering",
]

COHORTS = [
    ("combinators-selective", []),
    ("combinators-full", ["NPeggedFullMemo"]),
    ("direct-selective", ["NPeggedDirect"]),
    ("direct-full", ["NPeggedDirect", "NPeggedFullMemo"]),
]


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_cmd(cmd: list[str], timeout: int = 300) -> subprocess.CompletedProcess[str]:
    wrapped = [
        "prlimit",
        "--as=4294967296",
        "--",
        "timeout",
        "--kill-after=2s",
        f"{timeout}s",
        *cmd,
    ]
    return subprocess.run(wrapped, check=True, text=True, capture_output=True)


def cpu_model() -> str:
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("model name"):
                return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return platform.processor() or "unknown"


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    os.chdir(root)
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "performance/results/H06")
    build_dir = Path("build/H06/profile")
    out_dir.mkdir(parents=True, exist_ok=True)
    build_dir.mkdir(parents=True, exist_ok=True)

    library = sorted(str(p) for p in Path("src").rglob("*.d"))
    fixture = "benchmark/diagnostics/scanner_report.d"
    tracked = [*library, fixture, "tests/scanner_report.d", "scripts/scanner-report-profile.py"]
    sources_before = {p: sha256_file(Path(p)) for p in tracked}

    static_rows: list[list[str]] = []
    event_rows: list[list[str]] = []
    binary_hashes: dict[str, str] = {}
    commands: dict[str, list[str]] = {}

    for cohort, versions in COHORTS:
        outputs: dict[str, str] = {}
        for compiler in ("dmd", "ldc2"):
            runner = build_dir / f"{compiler}-{cohort}.runner"
            if compiler == "dmd":
                flags = [
                    "-Isrc",
                    "-J.",
                    "-defaultlib=druntime",
                    "-nothrow",
                    "-w",
                    "-checkaction=halt",
                    "-version=NPeggedScannerMetrics",
                    *(f"-version={v}" for v in versions),
                ]
            else:
                flags = [
                    "-Isrc",
                    "-J.",
                    "-defaultlib=druntime-ldc",
                    "-fno-exceptions",
                    "-w",
                    "-checkaction=halt",
                    "-O3",
                    "-release",
                    "-enable-asserts=true",
                    "-d-version=NPeggedScannerMetrics",
                    *(f"-d-version={v}" for v in versions),
                ]
            compile_cmd = [compiler, *flags, *library, fixture, f"-of={runner}"]
            commands[f"{compiler}-{cohort}"] = compile_cmd
            run_cmd(compile_cmd, timeout=300)
            binary_hashes[f"{compiler}-{cohort}"] = sha256_file(runner)
            proc = run_cmd([str(runner)], timeout=60)
            outputs[compiler] = proc.stdout

        if outputs["dmd"] != outputs["ldc2"]:
            raise RuntimeError(f"DMD and LDC scanner profiles differ for {cohort}")

        for line in outputs["ldc2"].splitlines():
            parts = line.split(",")
            if parts[0] == "static":
                if cohort == "combinators-selective":
                    static_rows.append(parts[1:])
            elif parts[0] == "row":
                event_rows.append(parts[1:])

    sources_after = {p: sha256_file(Path(p)) for p in tracked}
    if sources_before != sources_after:
        raise RuntimeError("Source hashes changed during H06 profile execution")

    static_csv = out_dir / "static-rules.csv"
    with static_csv.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["grammar", "rule", "emitted_regions", "root_regular_proven"])
        writer.writerows(static_rows)

    events_csv = out_dir / "scanner-events.csv"
    header = [
        "cohort",
        "grammar",
        "case",
        "mode",
        "accepted",
        "input_bytes",
        "rule_or_region",
        "calls",
        "eligible",
        "scan_calls",
        "scan_success",
        "scan_failure",
        "fast_success",
        "fast_failure",
        "original_calls",
        "replays",
        "examined_bytes",
        "original_bytes",
        "replayed_bytes",
        *(f"reason_{r}" for r in REASONS),
    ]
    with events_csv.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(header)
        writer.writerows(event_rows)

    hotspots = []
    for row in event_rows:
        if row[6] == "<total>":
            continue
        original_calls = int(row[14])
        replays = int(row[15])
        if replays > 0 or (row[3] in ("check", "records") and original_calls > 0):
            reason_counts = {
                REASONS[i]: int(row[19 + i])
                for i in range(len(REASONS))
                if int(row[19 + i]) > 0
            }
            hotspots.append(
                {
                    "cohort": row[0],
                    "grammar": row[1],
                    "case": row[2],
                    "mode": row[3],
                    "accepted": row[4] == "1",
                    "inputBytes": int(row[5]),
                    "region": row[6],
                    "calls": int(row[7]),
                    "eligible": int(row[8]),
                    "scanCalls": int(row[9]),
                    "scanSuccess": int(row[10]),
                    "scanFailure": int(row[11]),
                    "fastSuccess": int(row[12]),
                    "fastFailure": int(row[13]),
                    "originalCalls": original_calls,
                    "replays": replays,
                    "examinedBytes": int(row[16]),
                    "originalBytes": int(row[17]),
                    "replayedBytes": int(row[18]),
                    "reasons": reason_counts,
                }
            )

    dmd_ver = subprocess.run(["dmd", "--version"], check=True, text=True, capture_output=True).stdout.splitlines()[0]
    ldc_ver = subprocess.run(["ldc2", "--version"], check=True, text=True, capture_output=True).stdout.splitlines()[0]
    head = subprocess.run(["git", "rev-parse", "HEAD"], check=True, text=True, capture_output=True).stdout.strip()

    metadata = {
        "milestone": "H06",
        "diagnosticOnly": True,
        "timingClaim": False,
        "gitHeadBeforeCommit": head,
        "cpu": cpu_model(),
        "compilers": {"dmd": dmd_ver, "ldc2": ldc_ver},
        "limits": {"compileTimeoutSeconds": 300, "runTimeoutSeconds": 60, "addressSpaceBytes": 4294967296},
        "sources": sources_after,
        "binaries": binary_hashes,
        "commands": commands,
        "csvHashes": {
            "static-rules.csv": sha256_file(static_csv),
            "scanner-events.csv": sha256_file(events_csv),
        },
        "staticRuleCount": len(static_rows),
        "eventRowCount": len(event_rows),
    }
    (out_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (out_dir / "hotspots.json").write_text(json.dumps(hotspots, indent=2) + "\n")
    print(f"Wrote {len(static_rows)} static rows and {len(event_rows)} event rows to {out_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
