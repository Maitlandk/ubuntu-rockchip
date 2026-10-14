#!/bin/bash

set -eE
trap 'echo Error: in $0 on line $LINENO' ERR

cd "$(dirname -- "$(readlink -f -- "$0")")" && cd ..
mkdir -p build && cd build

if [[ -z ${SUITE} ]]; then
    echo "Error: SUITE is not set"
    exit 1
fi

# shellcheck source=/dev/null
source "../config/suites/${SUITE}.sh"

if [[ ${FLAVOR} != server ]]; then
    echo "Error: FLAVOR must be server"
    exit 1
fi

rootfs="ubuntu-${RELASE_VERSION}-preinstalled-${FLAVOR}-arm64.rootfs.tar.xz"
if [[ -f ${rootfs} ]]; then
    exit 0
fi

# Canonical's arm64 server cloud image, as its own livecd-rootfs builds
# it, with the kernel and boot loader removed. The image build adds the
# kernel. SHA256SUMS is signed by the UEC Image Automatic Signing Key.
url="https://cloud-images.ubuntu.com/releases/${SUITE}/release"
name="ubuntu-${RELASE_VERSION}-server-cloudimg-arm64-root.tar.xz"

tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT

(cd "${tmp_dir}" && curl -fsSL --remote-name-all "${url}"/{SHA256SUMS,SHA256SUMS.gpg,"${name}"})
gpgv --keyring /usr/share/keyrings/ubuntu-cloudimage-keyring.gpg "${tmp_dir}/SHA256SUMS.gpg" "${tmp_dir}/SHA256SUMS"
(cd "${tmp_dir}" && sha256sum --check --ignore-missing SHA256SUMS)

mv "${tmp_dir}/${name}" "${rootfs}"
