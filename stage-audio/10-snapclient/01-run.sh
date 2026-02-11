#!/bin/bash -e

install -v -m 644 files/snapclient.default "${ROOTFS_DIR}/etc/default/snapclient"

on_chroot << EOF
	systemctl disable snapclient.service
	/bin/su - "${FIRST_USER_NAME}" -c 'systemctl --user enable snapclient.service'
EOF
