#!/bin/bash -e

sed -i "s/TARGET_HOSTNAME/${TARGET_HOSTNAME}/g" "${ROOTFS_DIR}/etc/upmpdcli.conf"

on_chroot << EOF
	systemctl enable upmpdcli
EOF