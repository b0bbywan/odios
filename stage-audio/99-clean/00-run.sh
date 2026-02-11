#/bin/bash -e

wget "https://github.com/framps/raspberryTools/raw/master/raspiHandleKernels.sh" -O "${ROOTFS_DIR}/usr/local/bin/raspiHandleKernels.sh"
chown root:root "${ROOTFS_DIR}/usr/local/bin/raspiHandleKernels.sh" && chmod 755 "${ROOTFS_DIR}/usr/local/bin/raspiHandleKernels.sh"
install -v -m 644 "files/clean-kernels.service" "${ROOTFS_DIR}/etc/systemd/system/clean-kernels.service"

on_chroot << EOF
	sudo apt-get purge -y --auto-remove gcc-7-base gcc-8-base gcc-9-base gcc-10-base tasksel
	systemctl enable clean-kernels.service
EOF