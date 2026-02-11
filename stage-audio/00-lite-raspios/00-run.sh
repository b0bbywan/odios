#!/bin/bash -e

on_chroot << EOF

	apt-get purge -y 'linux-headers-*' || true

	apt-get purge -y \
		man-db manpages \
		apt-listchanges \
		build-essential gdb manpages-dev \
		python3-gpiozero python3-rpi.gpio python3-spidev \
		v4l-utils \
		nfs-common rpcbind \
		rpi-connect-lite \
		rpi-swap rpi-loop-utils \
		rpicam-apps-lite || true

	apt-get autoremove -y
EOF
