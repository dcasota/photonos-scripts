# sharukhan builder: runs Photon's build tooling (build.py, make, check_spec, SpecData,
# spec-generator, poi.py) with a pinned userland instead of the host's.
# Inputs are local and locked: the base image by ID (tagged by sharukhan after checking it),
# rpms/ by rpms.sha256, wheels/ by wheels.sha256. No network access during the build.
ARG BASE
FROM ${BASE}
COPY rpms.sha256 wheels.sha256 /tmp/lock/
COPY rpms/ /tmp/rpms/
COPY wheels/ /tmp/wheels/
COPY systemctl /usr/local/bin/systemctl
RUN cd /tmp/rpms && sha256sum -c /tmp/lock/rpms.sha256 >/dev/null \
 && cd /tmp/wheels && sha256sum -c /tmp/lock/wheels.sha256 >/dev/null
RUN tdnf -y -q --disablerepo="*" install /tmp/rpms/*.rpm \
 && python3 -m pip install --no-index --no-deps --root-user-action=ignore /tmp/wheels/*.whl >/dev/null \
 && rm -rf /tmp/rpms /tmp/wheels /tmp/lock /root/.cache
