#!/usr/bin/env python3
"""Measure one owned process without reading its screen or clipboard."""
import argparse
import ctypes
import json
from pathlib import Path
import subprocess
import time


class RUsageInfo(ctypes.Structure):
    # RUSAGE_INFO_V0 from the local macOS SDK's sys/resource.h.
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (name, ctypes.c_uint64)
        for name in (
            "user_time", "system_time", "pkg_idle_wakeups", "interrupt_wakeups",
            "pageins", "wired_size", "resident_size", "phys_footprint",
            "start_time", "exit_time",
        )
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=int, default=60)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("--seconds must be positive")
    libproc = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    libproc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    libproc.proc_pid_rusage.restype = ctypes.c_int
    started = time.monotonic()
    samples = []
    for index in range(args.seconds + 1):
        time.sleep(max(0, started + index - time.monotonic()))
        usage = RUsageInfo()
        if libproc.proc_pid_rusage(args.pid, 0, ctypes.byref(usage)) != 0:
            raise OSError(ctypes.get_errno(), "Cannot sample the requested process")
        cpu = subprocess.check_output(
            ["ps", "-p", str(args.pid), "-o", "time="], text=True
        ).strip().split(":")
        cpu_seconds = float(cpu[-1]) + int(cpu[-2]) * 60
        if len(cpu) > 2:
            cpu_seconds += int(cpu[-3]) * 3600
        samples.append({
            "elapsed_seconds": time.monotonic() - started,
            "cpu_seconds": cpu_seconds,
            "rss_mib": usage.resident_size / 1048576,
            "physical_footprint_mib": usage.phys_footprint / 1048576,
        })
    duration = samples[-1]["elapsed_seconds"] - samples[0]["elapsed_seconds"]
    result = {
        "pid": args.pid,
        "duration_seconds": duration,
        "average_cpu_percent": (samples[-1]["cpu_seconds"] - samples[0]["cpu_seconds"]) / duration * 100,
        "mean_rss_mib": sum(s["rss_mib"] for s in samples) / len(samples),
        "peak_rss_mib": max(s["rss_mib"] for s in samples),
        "mean_physical_footprint_mib": sum(s["physical_footprint_mib"] for s in samples) / len(samples),
        "peak_physical_footprint_mib": max(s["physical_footprint_mib"] for s in samples),
        "physical_memory_bytes": int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True)),
        "samples": samples,
        "scope": "One process; RSS and physical footprint are separate metrics. CPU uses the process CPU-time delta, not a ps lifetime average.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "samples"}, indent=2))


if __name__ == "__main__":
    main()
