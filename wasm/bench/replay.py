"""Replays the SymPy requests recorded from each module and times them.

Each wasm/bench/<module>.jsonl holds the request lines `landau` sent to
cas/worker.py while checking modules/<module>.lan. The same script runs on
native Python and under Pyodide, so the two can be compared: it prints one
JSON object with the import time, each module's time and a hash of its
replies (equal hashes mean equal results).

    PYTHONHASHSEED=0 .venv/bin/python wasm/bench/replay.py
"""

import hashlib
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "cas"))

t0 = time.perf_counter()
import sympy  # noqa: E402

import worker  # noqa: E402

import_time = time.perf_counter() - t0


def run():
    modules = {}
    for name in sorted(os.listdir(HERE)):
        if not name.endswith(".jsonl"):
            continue
        with open(os.path.join(HERE, name)) as f:
            lines = [l for l in f if l.strip()]
        # every check starts a fresh worker, so start each module with a cold cache
        sympy.core.cache.clear_cache()
        digest = hashlib.sha256()
        t = time.perf_counter()
        for line in lines:
            try:
                reply = {"ok": worker.handle(json.loads(line))}
            except Exception as e:
                reply = {"error": f"{type(e).__name__}: {e}"}
            digest.update(json.dumps(reply).encode())
        modules[name[:-6]] = {"requests": len(lines), "seconds": round(time.perf_counter() - t, 3), "hash": digest.hexdigest()[:12]}
    return {"python": sys.version.split()[0], "sympy": sympy.__version__, "import_seconds": round(import_time, 3), "modules": modules}


if __name__ == "__main__":
    print(json.dumps(run()))
