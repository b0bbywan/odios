#!/bin/bash -e

install -v -m 644 files/bobbywan.sources "${ROOTFS_DIR}/etc/apt/sources.list.d/bobbywan.sources"
install -v -o 1000 -g 29 -m 644 'files/.mpdignore' "${ROOTFS_DIR}/media/USB/.mpdignore"

on_chroot << EOF
	apt-get update
EOF
