FROM ghcr.io/open-webui/open-webui:v0.9.6
COPY docker/open-webui/patch_web_search_retrieval.py /tmp/patch_web_search_retrieval.py
RUN python3 /tmp/patch_web_search_retrieval.py && rm /tmp/patch_web_search_retrieval.py
