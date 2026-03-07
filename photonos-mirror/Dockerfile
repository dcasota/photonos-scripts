FROM photon:5.0-20251221

LABEL maintainer="dcasota"
LABEL description="Photon OS offline mirror: documentation site, Broadcom Artifactory repo, and GitHub repositories"

ARG MIRROR_DIR=/mirror

# Install required tools
RUN tdnf install -y \
        git \
        wget \
        tar \
        curl \
        ca-certificates \
    && tdnf clean all

ENV MIRROR_DIR=${MIRROR_DIR}

# Create mirror directory structure
RUN mkdir -p \
    ${MIRROR_DIR}/docs \
    ${MIRROR_DIR}/artifactory \
    ${MIRROR_DIR}/repos

# ---------------------------------------------------------------------------
# Phase 1: Mirror the Photon OS documentation website
# ---------------------------------------------------------------------------
RUN wget --mirror \
         --convert-links \
         --adjust-extension \
         --page-requisites \
         --no-parent \
         --reject-regex='.*\?.*' \
         --directory-prefix=${MIRROR_DIR}/docs \
         --no-host-directories \
         --cut-dirs=1 \
         --tries=3 \
         --timeout=30 \
         --wait=1 \
         https://vmware.github.io/photon/ \
    || echo "Documentation mirror completed (some assets may have been unavailable)"

# ---------------------------------------------------------------------------
# Phase 2: Mirror the Broadcom Artifactory repository index
# ---------------------------------------------------------------------------
RUN wget --mirror \
         --no-parent \
         --reject "index.html*" \
         --directory-prefix=${MIRROR_DIR}/artifactory \
         --no-host-directories \
         --cut-dirs=1 \
         --tries=3 \
         --timeout=60 \
         --wait=1 \
         -l 2 \
         https://packages.broadcom.com/artifactory/photon/ \
    || echo "Artifactory index mirror completed (depth-limited to avoid full RPM download)"

# ---------------------------------------------------------------------------
# Phase 3: Clone GitHub repositories
# ---------------------------------------------------------------------------
RUN git clone --depth 1 https://github.com/vmware/photon.git \
        ${MIRROR_DIR}/repos/photon \
    && git clone --depth 1 https://github.com/vmware/photon-os-installer.git \
        ${MIRROR_DIR}/repos/photon-os-installer \
    && git clone --depth 1 https://github.com/vmware/tdnf.git \
        ${MIRROR_DIR}/repos/tdnf \
    && git clone --depth 1 https://github.com/vmware/photon-docker-image.git \
        ${MIRROR_DIR}/repos/photon-docker-image \
    && git clone --depth 1 https://github.com/vmware/dod-compliance-and-automation.git \
        ${MIRROR_DIR}/repos/dod-compliance-and-automation \
    && git clone --depth 1 https://github.com/vmware/open-vm-tools.git \
        ${MIRROR_DIR}/repos/open-vm-tools \
    && git clone --depth 1 https://github.com/vmware/pmd-next-gen.git \
        ${MIRROR_DIR}/repos/pmd-next-gen \
    && git clone --depth 1 https://github.com/vmware/pmd.git \
        ${MIRROR_DIR}/repos/pmd

VOLUME ${MIRROR_DIR}
WORKDIR ${MIRROR_DIR}

CMD ["sh", "-c", "echo 'Photon OS Mirror contents:' && du -sh ${MIRROR_DIR}/*"]
