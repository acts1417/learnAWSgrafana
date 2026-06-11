FROM nvcr.io/nvidia/cuda:12.6.3-base-ubuntu22.04
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 && \
    rm -rf /var/lib/apt/lists/*
COPY scripts/gpu-process-exporter.py /exporter.py
EXPOSE 9401
CMD ["python3", "/exporter.py"]
