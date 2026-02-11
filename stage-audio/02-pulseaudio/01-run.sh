#!/bin/bash -e

install -v -m 755 files/pulse-tcp.sh "${ROOTFS_DIR}/usr/local/bin/pulse-tcp.sh"
install -v -m 644 files/pulse-tcp.service "${ROOTFS_DIR}/usr/lib/systemd/user/pulse-tcp.service"

on_chroot << EOF
    /bin/su - "${FIRST_USER_NAME}" -c 'systemctl --user enable pulseaudio.service'
    /bin/su - "${FIRST_USER_NAME}" -c 'systemctl --user enable pulse-tcp.service'
EOF
