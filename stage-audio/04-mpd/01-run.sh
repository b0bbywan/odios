#!/bin/bash -e

install -v -o 1000 -g 29 -m 775 -d "${ROOTFS_DIR}/media/USB"

install -v -o 1000 -g 1000 -m 700 -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/mpd"
install -v -o 1000 -g 1000 -m 700 -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.local/share/mpd"
install -v -o 1000 -g 1000 -m 600 "${ROOTFS_DIR}/etc/mpd.conf" "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.config/mpd/mpd.conf"
install -v -o 1000 -g 1000 -m 700 -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.local/share/mpd/playlists"
install -v -o 1000 -g 1000 -m 644 /dev/null "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.local/share/mpd/state"
install -v -o 1000 -g 1000 -m 700 -d "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/.local/share/mpd/cache"
on_chroot << EOF
  systemctl disable mpd.socket mpd.service
  /bin/su - "${FIRST_USER_NAME}" -c 'systemctl --user enable mpd.service'
EOF
