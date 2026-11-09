"""Configure the public DID facade to use IdentityHub's published document."""

import json
from pathlib import Path
import re
from urllib.parse import quote, unquote


def render_proxy_config(document):
    did = document.get("id", "")
    if not isinstance(did, str) or not did.startswith("did:web:"):
        raise ValueError("The issuer bootstrap document must identify a did:web DID")
    segments = did[len("did:web:"):].split(":")
    host = unquote(segments[0])
    if not re.fullmatch(r"[A-Za-z0-9.-]+(?::[0-9]+)?", host):
        raise ValueError("Invalid issuer DID host")
    path_segments = [unquote(segment) for segment in segments[1:]]
    if any(not segment or segment in {".", ".."} for segment in path_segments):
        raise ValueError("Invalid issuer DID path")
    path = "/" + "/".join(quote(segment, safe="") for segment in path_segments) if path_segments else "/.well-known"
    # Use the canonical DID host/path, not the external facade's hostname.
    # IdentityHub selects its published document from those request values.
    return f"""events {{}}
http {{
  server {{
    listen 80;
    location = /did.json {{
      proxy_pass http://dataspace-issuer-service:10016{path}/did.json;
      proxy_set_header Host {host};
      proxy_set_header X-Forwarded-Host {host};
      proxy_set_header X-Forwarded-Proto https;
      proxy_hide_header Cache-Control;
      add_header Cache-Control "no-store" always;
    }}
  }}
}}
"""


if __name__ == "__main__":
    document = json.loads(Path("/bootstrap/did.json").read_text())
    Path("/generated/nginx.conf").write_text(render_proxy_config(document))
