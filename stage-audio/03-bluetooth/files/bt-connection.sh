#!/bin/bash
logger "${NAME} successfully connected"
PI_USER=$(id --user --name 1000)
if [[ $(whoami) == "root" ]]; then
	su - "${PI_USER}" -c 'pactl upload-sample /usr/local/share/sounds/success.wav && pactl play-sample success'
else
	pactl upload-sample /usr/local/share/sounds/success.wav && pactl play-sample success
fi
