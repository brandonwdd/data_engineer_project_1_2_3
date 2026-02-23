"""Silver merge entrypoint from Bronze to Silver."""
from __future__ import annotations

import os
import sys

_PROJECT_ROOT = os.environ.get("PROJECT_ROOT", "/app")
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from streaming.spark.silver_merge.job import run


def main() -> None:
    run()


if __name__ == "__main__":
    main()
