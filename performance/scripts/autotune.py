#!/usr/bin/env python3
"""X3: offline per-family configuration profile from recorded runs.

Reads two or more run directories (each with summary.csv and metadata.json), compares
median_ns per workload for the npegged implementation, and freezes one choice per family:
the candidate with the lowest geometric-mean time over the workloads all candidates share.
A family falls back to the first candidate (the default) unless another beats it by MARGIN
on at least MIN_WORKLOADS shared workloads and does not regress any workload by more than
WORST. Nothing is measured here; the profile is data derived from performance/ only.
"""
import csv, json, math, sys, os

MARGIN = 0.03
MIN_WORKLOADS = 3
WORST = 1.25


def load(run_dir):
    rows = {}
    with open(os.path.join(run_dir, "summary.csv")) as f:
        for r in csv.DictReader(f):
            if r["implementation"] != "npegged":
                continue
            try:
                rows[r["workload_id"]] = float(r["median_ns"])
            except ValueError:
                pass
    return rows


def family(workload):
    return workload.split("/")[0]


def geomean(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))


def choose(candidates):
    """candidates: ordered {name: {workload: ns}}; first is the default."""
    names = list(candidates)
    shared = set.intersection(*(set(c) for c in candidates.values()))
    fams = {}
    for w in sorted(shared):
        fams.setdefault(family(w), []).append(w)
    profile = {}
    for fam, ws in sorted(fams.items()):
        choice, reason = names[0], "default"
        if len(ws) >= MIN_WORKLOADS:
            base = geomean([candidates[names[0]][w] for w in ws])
            for n in names[1:]:
                g = geomean([candidates[n][w] for w in ws])
                worst = max(candidates[n][w] / candidates[names[0]][w] for w in ws)
                if g < base * (1 - MARGIN) and worst <= WORST:
                    choice, reason, base = n, "geomean %.3f of default, worst %.3f" % (g / geomean([candidates[names[0]][w] for w in ws]), worst), g
        profile[fam] = {"choice": choice, "workloads": len(ws), "reason": reason}
    return profile


def main(argv):
    if len(argv) < 3:
        print("usage: autotune.py NAME=RUN_DIR NAME=RUN_DIR [...] (first is the default)")
        return 2
    cands = {}
    for a in argv[1:]:
        n, d = a.split("=", 1)
        cands[n] = load(d)
    print(json.dumps(choose(cands), indent=2, sort_keys=True))
    return 0


def selftest():
    c = {"a": {"x/1": 10, "x/2": 10, "x/3": 10, "y/1": 10}, "b": {"x/1": 5, "x/2": 5, "x/3": 5, "y/1": 1}}
    p = choose(c)
    assert p["x"]["choice"] == "b" and p["y"]["choice"] == "a", p
    c["b"]["x/3"] = 20
    assert choose(c)["x"]["choice"] == "a"


if __name__ == "__main__":
    selftest()
    sys.exit(main(sys.argv))
