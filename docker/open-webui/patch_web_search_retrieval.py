"""Build-time patch for an open-webui v0.9.6 regression (no upstream fix yet).

get_sources_from_items() in retrieval/utils.py gates the bare collection_name
fallback behind BYPASS_RETRIEVAL_ACCESS_CONTROL but never added a matching
dispatch branch for type == 'web_search' items, so server-generated
web-search-* collections fall through to that gate and get silently dropped
instead of queried -- the model answers with no sources every time.

Regression: open-webui commit ee47c9c83 (2026-06-01), shipped in v0.9.6.
Upstream fix (same change, unmerged): https://github.com/open-webui/open-webui/pull/25600
Tracking issue: https://github.com/open-webui/open-webui/issues/25585

Remove this file and the Dockerfile build step once PR #25600 (or an
equivalent fix) ships in a released open-webui image.
"""

path = "/app/backend/open_webui/retrieval/utils.py"
with open(path) as f:
    lines = f.readlines()

anchor = "        elif item.get('docs'):\n"
idx = lines.index(anchor)

new_block = [
    "        elif item.get('type') == 'web_search' and item.get('collection_name'):\n",
    "            # Trusted server-generated collection; authorized by\n",
    "            # filter_accessible_collections below (allowlists web-search-*).\n",
    "            collection_names.append(item['collection_name'])\n",
]

lines[idx:idx] = new_block

with open(path, "w") as f:
    f.writelines(lines)
