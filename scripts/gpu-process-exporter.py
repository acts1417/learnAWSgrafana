#!/usr/bin/env python3
"""Per-process GPU metrics exporter using nvidia-smi."""
import subprocess
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 9401
REFRESH_SECONDS = 5

_lock = threading.Lock()
_metrics: dict = {}


def _run_pmon() -> dict:
    """SM and memory utilization per process via nvidia-smi pmon."""
    try:
        r = subprocess.run(
            ["nvidia-smi", "pmon", "-s", "u", "-c", "1"],
            capture_output=True, text=True, timeout=15,
        )
        out = {}
        for line in r.stdout.splitlines():
            if line.startswith("#") or not line.strip():
                continue
            parts = line.split()
            if len(parts) < 7 or parts[1] == "-":
                continue
            try:
                out[parts[1]] = {
                    "gpu": parts[0],
                    "pid": parts[1],
                    "sm": int(parts[3]) if parts[3] != "-" else 0,
                    "mem_pct": int(parts[4]) if parts[4] != "-" else 0,
                    "command": parts[7] if len(parts) > 7 else "unknown",
                    "mem_mib": 0,
                }
            except (ValueError, IndexError):
                pass
        return out
    except Exception:
        return {}


def _run_query_apps() -> dict:
    """Memory used per process via nvidia-smi --query-compute-apps."""
    try:
        r = subprocess.run(
            [
                "nvidia-smi",
                "--query-compute-apps=pid,process_name,used_gpu_memory",
                "--format=csv,noheader,nounits",
            ],
            capture_output=True, text=True, timeout=10,
        )
        out = {}
        for line in r.stdout.splitlines():
            if not line.strip():
                continue
            parts = [p.strip() for p in line.split(",")]
            if len(parts) < 3:
                continue
            try:
                pid, name, mem = parts[0], parts[1], parts[2]
                out[pid] = {"name": name.split("/")[-1], "mem_mib": int(mem)}
            except (ValueError, IndexError):
                pass
        return out
    except Exception:
        return {}


def _collect_loop():
    while True:
        pmon = _run_pmon()
        apps = _run_query_apps()

        merged = {}
        for pid, info in pmon.items():
            entry = dict(info)
            if pid in apps:
                entry["mem_mib"] = apps[pid]["mem_mib"]
                # prefer longer process name from query-compute-apps
                if len(apps[pid]["name"]) > len(entry["command"]):
                    entry["command"] = apps[pid]["name"]
            merged[pid] = entry

        # processes that appear only in apps (memory-resident but no SM activity)
        for pid, info in apps.items():
            if pid not in merged:
                merged[pid] = {
                    "gpu": "0", "pid": pid,
                    "sm": 0, "mem_pct": 0,
                    "mem_mib": info["mem_mib"],
                    "command": info["name"],
                }

        with _lock:
            _metrics.clear()
            _metrics.update(merged)

        time.sleep(REFRESH_SECONDS)


def _render() -> str:
    with _lock:
        snap = dict(_metrics)

    lines = []
    for metric, help_text, field in [
        ("nvidia_process_sm_util",
         "SM (compute) utilization per GPU process (%)", "sm"),
        ("nvidia_process_mem_util",
         "Memory utilization per GPU process (%)", "mem_pct"),
        ("nvidia_process_mem_used_mib",
         "GPU memory used per process (MiB)", "mem_mib"),
    ]:
        lines += [f"# HELP {metric} {help_text}", f"# TYPE {metric} gauge"]
        for pid, m in snap.items():
            lbl = f'gpu="{m["gpu"]}",pid="{pid}",command="{m["command"]}"'
            lines.append(f"{metric}{{{lbl}}} {m.get(field, 0)}")

    return "\n".join(lines) + "\n"


class _Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/metrics":
            self.send_response(404)
            self.end_headers()
            return
        body = _render().encode()
        self.send_response(200)
        self.send_header("Content-Type",
                         "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", len(body))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    t = threading.Thread(target=_collect_loop, daemon=True)
    t.start()
    time.sleep(2)  # let first collection complete before serving
    print(f"GPU process exporter listening on :{PORT}", flush=True)
    HTTPServer(("", PORT), _Handler).serve_forever()
