#!/bin/bash -e

wget "https://www.lesbonscomptes.com/pages/lesbonscomptes.gpg" -O "${ROOTFS_DIR}/usr/share/keyrings/lesbonscomptes.gpg"
chown root:root "${ROOTFS_DIR}/usr/share/keyrings/lesbonscomptes.gpg" && chmod 644 "${ROOTFS_DIR}/usr/share/keyrings/lesbonscomptes.gpg"
install -v -m 644 files/upmpdcli.sources "${ROOTFS_DIR}/etc/apt/sources.list.d/upmpdcli.sources"

on_chroot << EOF
	apt-get update
EOF
