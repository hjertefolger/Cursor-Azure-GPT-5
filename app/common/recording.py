"""Lightweight recording helpers for debugging request/response flows.

Artifacts are stored under the project-level ``recordings/`` folder using a
monotonically increasing numeric prefix so related request/response files are
easy to correlate.
"""

import json
import os
from functools import wraps
from typing import Any, Dict

from flask import current_app, has_app_context

RECORDINGS_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "recordings")

# Private, module-level counter tracking the latest recording index.
__LAST_RECORDING_INDEX = 0

# Initialize the counter based on existing files in the recordings directory so
# that subsequent runs continue incrementing from the maximum observed index.
files = os.listdir(RECORDINGS_DIR)
for file in files:
    try:
        recording_index = int(file.split("_")[0])
        if recording_index > __LAST_RECORDING_INDEX:
            __LAST_RECORDING_INDEX = recording_index
    except (ValueError, IndexError):
        # Ignore unrelated files that do not follow the "<index>_<name>.*" pattern
        pass


def config_bypass(func):
    """Bypass the wrapped function when RECORD_TRAFFIC is disabled."""

    @wraps(func)
    def wrapper(*args, **kwargs):
        enabled = False
        if has_app_context():
            enabled = current_app.config["RECORD_TRAFFIC"]
        if not enabled:
            return None
        return func(*args, **kwargs)

    return wrapper


@config_bypass
def increment_last_recording() -> None:
    """Advance the shared recording index for a new request lifecycle."""

    global __LAST_RECORDING_INDEX
    __LAST_RECORDING_INDEX += 1


@config_bypass
def record_payload(payload: Dict[str, Any], name: str) -> None:
    """Write a JSON payload for the current recording index."""

    file_name = f"{__LAST_RECORDING_INDEX}_{name}.json"
    file_path = os.path.join(RECORDINGS_DIR, file_name)
    with open(file_path, "w") as f:
        json.dump(payload, f, indent=2)


@config_bypass
def record_sse(sse: bytes, name: str) -> None:
    """Write raw SSE bytes for the current recording index."""

    file_name = f"{__LAST_RECORDING_INDEX}_{name}.sse"
    file_path = os.path.join(RECORDINGS_DIR, file_name)
    with open(file_path, "wb") as f:
        f.write(sse)
