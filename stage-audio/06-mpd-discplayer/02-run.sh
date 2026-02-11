#!/bin/bash -e

install -v -o 1000 -g 1000 -m 700 -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/mpd-discplayer"
install -v -m 644 files/mpd-discplayer.yaml "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/mpd-discplayer/config.yaml"

on_chroot << EOF
	/bin/su - "${FIRST_USER_NAME}" -c 'systemctl --user enable mpd-discplayer.service'
EOF