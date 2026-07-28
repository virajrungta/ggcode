"""Export the OpenAPI spec to contracts/openapi.yaml.

The Pydantic models are the source of truth for REST; this makes the spec a
build artifact rather than a second thing to keep in sync by hand. CI runs it
and fails if the tree changes, so a route edit that skips the export cannot
merge.

    python -m app.export_openapi
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

OUTPUT = Path(__file__).resolve().parents[2] / "contracts" / "openapi.yaml"


def main() -> int:
    import os

    # The spec must not depend on deployment config, and building it under
    # production settings would trip the startup guards.
    os.environ.setdefault("GG_AUTH_MODE", "dev")
    os.environ.setdefault("GG_ENV", "development")

    from app.main import app

    spec = app.openapi()

    try:
        import yaml
        text = yaml.safe_dump(spec, sort_keys=False, allow_unicode=True, width=100)
    except ImportError:
        text = json.dumps(spec, indent=2, ensure_ascii=False) + "\n"
        print("pyyaml not installed — wrote JSON (valid OpenAPI either way)", file=sys.stderr)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(text)
    print(f"wrote {OUTPUT} ({len(spec['paths'])} paths)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
