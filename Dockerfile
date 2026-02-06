# Dockerfile.txt
ARG BASE_IMAGE=ubuntu:22.04
FROM ${BASE_IMAGE}

ARG WARP_VERSION
ARG GOST_VERSION=3.0.0
ARG COMMIT_SHA
ARG TARGETPLATFORM

LABEL org.opencontainers.image.authors="cmj2002"
LABEL org.opencontainers.image.url="https://github.com/cmj2002/warp-docker"
LABEL WARP_VERSION=${WARP_VERSION}
LABEL GOST_VERSION=${GOST_VERSION}
LABEL COMMIT_SHA=${COMMIT_SHA}

COPY entrypoint.sh /entrypoint.sh
COPY ./healthcheck /healthcheck

RUN case ${TARGETPLATFORM} in \
      "linux/amd64")   export GOST_ASSET_ARCH="amd64" ;; \
      "linux/arm64")   export GOST_ASSET_ARCH="arm64" ;; \
      *) echo "Unsupported TARGETPLATFORM: ${TARGETPLATFORM}" && exit 1 ;; \
    esac && \
    echo "Building for ${TARGETPLATFORM} with GOST ${GOST_VERSION}" && \
    apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y curl gnupg lsb-release sudo jq ipcalc ca-certificates && \
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-client.list && \
    apt-get update && \
    apt-get install -y cloudflare-warp && \
    apt-get clean && \
    apt-get autoremove -y && \
    if [ -n "${GOST_VERSION}" ]; then \
      API_URL="https://api.github.com/repos/ginuerzh/gost/releases/tags/v${GOST_VERSION}"; \
    else \
      API_URL="https://api.github.com/repos/ginuerzh/gost/releases/latest"; \
    fi && \
    echo "Fetching GOST release metadata: ${API_URL}" && \
    GOST_URL="$(curl -fsSL "${API_URL}" | jq -r '.assets[].browser_download_url' | grep -E "linux_${GOST_ASSET_ARCH}\\.tar\\.gz$" | head -n 1)" && \
    if [ -z "${GOST_URL}" ] || [ "${GOST_URL}" = "null" ]; then \
      echo "Failed to find matching GOST asset for arch ${GOST_ASSET_ARCH} (expected linux_${GOST_ASSET_ARCH}.tar.gz)"; \
      exit 1; \
    fi && \
    echo "Downloading GOST: ${GOST_URL}" && \
    curl -fsSL -o /tmp/gost.tar.gz "${GOST_URL}" && \
    tar -xzf /tmp/gost.tar.gz -C /usr/bin gost && \
    rm -f /tmp/gost.tar.gz && \
    chmod +x /usr/bin/gost && \
    chmod +x /entrypoint.sh && \
    chmod +x /healthcheck/index.sh && \
    useradd -m -s /bin/bash warp && \
    echo "warp ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/warp

USER warp

RUN mkdir -p /home/warp/.local/share/warp && \
    echo -n 'yes' > /home/warp/.local/share/warp/accepted-tos.txt

ENV GOST_ARGS="-L :1080"
ENV WARP_SLEEP=2
ENV REGISTER_WHEN_MDM_EXISTS=
ENV WARP_LICENSE_KEY=
ENV BETA_FIX_HOST_CONNECTIVITY=
ENV WARP_ENABLE_NAT=

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD /healthcheck/index.sh

ENTRYPOINT ["/entrypoint.sh"]
