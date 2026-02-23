"""Bronze raw_cdc ingest entrypoint."""
from __future__ import annotations

import os
import sys

# Ensure project root on path when running as spark-submit entrypoint
_PROJECT_ROOT = os.environ.get("PROJECT_ROOT", "/app")
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from streaming.spark.bronze_ingest.job import run


def main() -> None:
    run()


if __name__ == "__main__":
    main()
