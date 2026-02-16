#!/bin/bash

set -e

rpmdir=${1:-rpms}

build_dir="build"

[ -d ${build_dir} ] && rm -r ${build_dir}
mkdir -p ${build_dir}

cmake -S . -B ${build_dir}

./scripts/build-tdnf-rpms ${rpmdir}

createrepo ${rpmdir}
