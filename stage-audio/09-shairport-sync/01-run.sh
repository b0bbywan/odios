#!/bin/bash -e

install -v -m 644 files/shairport-sync.service "${ROOTFS_DIR}/usr/lib/systemd/user/shairport-sync.service"
sed -i "s/FIRST_USER_NAME/${FIRST_USER_NAME}/g" "${ROOTFS_DIR}/usr/share/dbus-1/system.d/shairport-sync-dbus-policy.conf"
sed -i "s/FIRST_USER_NAME/${FIRST_USER_NAME}/g" "${ROOTFS_DIR}/usr/share/dbus-1/system.d/shairport-sync-mpris-policy.conf"

on_chroot << EOF
	systemctl disable shairport-sync.service
	/bin/su - "${FIRST_USER_NAME}" -c 'systemctl --user enable shairport-sync.service'
EOF
