#!/usr/bin/env python3
"""Regression runner for the pacemaker testbench (Vivado xsim).

Builds the design once per configuration, runs the directed tests and several
random seeds, and writes sim/regress/report.md.

  python sim/regress.py                    clean build + every injected fault
  python sim/regress.py --builds clean     only the clean build
  python sim/regress.py --seeds 5          random seeds 1..5

A clean build must pass everything. Each fault build (FI_* defines in
rtl/pacemaker.v) must FAIL at least one run, which shows the checkers can
actually catch that bug.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
VIV = Path(r"C:\Xilinx\Vivado\2020.2\bin")
FAULTS = ["FI_AV", "FI_PVARP", "FI_AP_EARLY", "FI_NODZ", "FI_XBLANK"]


def run(cmd, cwd):
    """Run a Vivado .bat wrapper. Every argument is quoted because the wrappers split on '='."""
    line = " ".join(f'"{c}"' for c in cmd)
    # cmd /c strips the outer quotes, so wrap the whole line in one more pair
    p = subprocess.run(f'cmd /c "{line}"', cwd=cwd, shell=True, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def build(name, define, workdir):
    workdir.mkdir(parents=True, exist_ok=True)
    defs = ["-d", define] if define else []
    for cmd in (
        [VIV / "xvlog.bat", *defs, ROOT / "rtl" / "pacemaker.v"],
        [VIV / "xvlog.bat", "-sv", ROOT / "tb" / "tb_pacemaker.sv"],
        [VIV / "xelab.bat", "-debug", "typical", "-timescale", "1ns/1ps", "tb_pacemaker", "-s", "sim"],
    ):
        rc, out = run([str(c) for c in cmd], workdir)
        if "ERROR:" in out and "Built simulation snapshot" not in out:
            return False, out
    # check the snapshot, not just exit codes (OneDrive can lock temp files)
    if not (workdir / "xsim.dir" / "sim" / "xsimk.exe").exists():
        return False, "snapshot was not created"
    return True, ""


def simulate(workdir, test, seed):
    log = workdir / f"{test}_{seed}.log"
    rc, out = run(
        [str(VIV / "xsim.bat"), "sim", "-runall", "-log", str(log),
         "-testplusarg", f"TEST={test}", "-sv_seed", str(seed)],
        workdir,
    )
    text = log.read_text(errors="replace") if log.exists() else out
    if "TEST PASSED" in text:
        status = "PASS"
    elif "TEST FAILED" in text:
        status = "FAIL"
    else:
        status = "CRASH"
    first = next((l.strip() for l in text.splitlines() if l.startswith("ERROR")), "")
    n_err = len(re.findall(r"^ERROR", text, flags=re.M))
    return status, n_err, first


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--builds", nargs="*", default=["clean"] + FAULTS)
    ap.add_argument("--seeds", type=int, default=3)
    args = ap.parse_args()

    runs = [("directed", 1)] + [("random", s) for s in range(1, args.seeds + 1)]
    lines = ["# Pacemaker regression report", ""]
    ok = True
    for name in args.builds:
        define = None if name == "clean" else name
        workdir = ROOT / "sim" / "regress" / name
        built, out = build(name, define, workdir)
        lines += [f"## build: {name}", ""]
        if not built:
            lines += ["BUILD FAILED", "```", out[-1500:], "```", ""]
            ok = False
            continue
        lines += ["| test | seed | status | errors | first error |", "|---|---|---|---|---|"]
        results = []
        for test, seed in runs:
            status, n_err, first = simulate(workdir, test, seed)
            results.append(status)
            lines.append(f"| {test} | {seed} | {status} | {n_err} | {first} |")
            print(f"{name:12s} {test:9s} seed {seed}: {status} ({n_err} errors)", flush=True)
        caught = any(r != "PASS" for r in results)
        if name == "clean":
            verdict = "all runs pass" if not caught else "UNEXPECTED FAILURES"
            ok &= not caught
        else:
            verdict = "fault caught" if caught else "FAULT NOT CAUGHT"
            ok &= caught
        lines += ["", f"**{verdict}**", ""]
    report = ROOT / "sim" / "regress" / "report.md"
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("\n".join(lines), encoding="utf-8")
    print(f"report: {report}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
