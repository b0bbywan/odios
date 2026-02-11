# Audio Streaming System Installer

Installeur Ansible "curl | bash" pour configurer un système audio/multimédia complet sur Debian/Ubuntu.

## 🎵 Composants

### Core (installés par défaut)
- **PulseAudio** - Serveur audio avec streaming réseau (TCP + Zeroconf)
- **Bluetooth Audio** - Agent d'authentification et connexion automatique
- **MPD** - Music Player Daemon avec support USB, CD/DVD et réseau

### Optionnels (sur demande)
- **Spotifyd** - Spotify Connect daemon
- **Shairport Sync** - Récepteur AirPlay
- **Snapcast** - Client multi-room audio
- **UPnP/DLNA** - Renderer pour contrôle depuis applications UPnP
- **MPD DiscPlayer** - Support CD/DVD pour MPD

## 📋 Prérequis

- OS: Debian 10+, Ubuntu 20.04+, ou Raspberry Pi OS
- Architecture: ARM (armv6l, armv7l, aarch64) ou x86_64
- Sudo access
- Connexion Internet
- 500 MB d'espace disque libre

## 🚀 Installation

### Installation directe (recommandée pour testing)

```bash
cd installer
./build.sh          # Génère install.sh
./install.sh        # Lance l'installation
```

### Installation depuis URL (production)

```bash
curl -fsSL https://example.com/install.sh | bash
```

### Installation avec review (sécurité)

```bash
curl -fsSL https://example.com/install.sh -o install.sh
less install.sh     # Reviewer le script
chmod +x install.sh
./install.sh
```

## ⚙️ Configuration

L'installeur demande interactivement:

- **Hostname** - Nom pour l'advertising des services (défaut: hostname actuel)
- **User cible** - User système pour les services (défaut: $USER)
- **PIN Bluetooth** - Code PIN pour pairing (défaut: 0000)
- **Composants optionnels** - Choix des composants à installer (y/N)

### Variables d'environnement (automation)

Pour une installation non-interactive:

```bash
export TARGET_HOSTNAME="raspiaudio"
export TARGET_USER="pi"
export BLUETOOTH_PIN="1234"
export INSTALL_SPOTIFYD="y"
export INSTALL_SHAIRPORT_SYNC="y"
export INSTALL_SNAPCLIENT="n"
export INSTALL_UPMPDCLI="y"
export INSTALL_MPD_DISCPLAYER="n"

./install.sh
```

## 🏗️ Architecture

### Structure du projet

```
installer/
├── README.md                    # Ce fichier
├── build.sh                     # Script de build
├── bootstrap.sh                 # Template du script d'installation
├── install.sh                   # Installeur généré (après build.sh)
└── ansible/
    ├── playbook.yml             # Playbook principal
    ├── inventory/localhost.yml  # Inventory localhost
    ├── group_vars/all.yml       # Variables par défaut
    └── roles/
        ├── common/              # Prérequis système
        ├── pulseaudio/          # PulseAudio + modules réseau
        ├── bluetooth/           # Bluetooth audio
        ├── mpd/                 # Music Player Daemon
        ├── spotifyd/            # Spotify Connect (optionnel)
        ├── shairport_sync/      # AirPlay (optionnel)
        ├── snapclient/          # Snapcast (optionnel)
        ├── upmpdcli/            # UPnP/DLNA (optionnel)
        └── mpd_discplayer/      # CD/DVD player (optionnel)
```

### Fonctionnement

1. **bootstrap.sh** - Script bash qui:
   - Affiche une bannière
   - Demande la configuration (prompts interactifs)
   - Vérifie les prérequis (OS, architecture, sudo, réseau, espace disque)
   - Installe Ansible si nécessaire
   - Extrait le playbook Ansible embarqué
   - Lance le playbook avec les variables collectées
   - Nettoie les fichiers temporaires

2. **build.sh** - Script de build qui:
   - Crée un tarball de ansible/
   - Encode en base64
   - Injecte dans bootstrap.sh à la place du marqueur `# __PLAYBOOK_ARCHIVE__`
   - Génère install.sh final

3. **Playbook Ansible** - Configure le système:
   - Détecte l'architecture (ARM/x86_64)
   - Exécute les roles CORE (common, pulseaudio, bluetooth, mpd)
   - Exécute les roles optionnels selon la configuration
   - Active les services systemd user
   - Configure l'auto-login console
   - Affiche un résumé de l'installation

## 🧪 Tests

### Test du playbook Ansible seul

```bash
cd ansible
ansible-playbook playbook.yml \
  -e "target_hostname=test" \
  -e "target_user=$USER" \
  -e "bluetooth_pin=1234"
```

### Test de l'installeur complet

```bash
cd installer
./build.sh
./install.sh
```

### Test d'idempotence

```bash
./install.sh  # Première exécution
./install.sh  # Deuxième exécution (doit montrer "ok", pas "changed")
```

### Vérification des services

```bash
# Services user
systemctl --user status pulseaudio pulse-tcp mpd

# Modules PulseAudio
pactl list modules | grep -E "tcp|zeroconf"

# Bluetooth
bluetoothctl show

# MPD
mpc status
```

## 📝 Notes techniques

### UID dynamique

Le playbook détecte automatiquement l'UID de l'utilisateur cible pour configurer:
- Socket Unix MPD: `/run/user/{UID}/mpd.socket`
- XDG_RUNTIME_DIR pour les services systemd user

### Services systemd user

Les services audio tournent en mode user (pas system) pour:
- Accès direct aux devices audio de l'utilisateur
- Isolation par utilisateur
- Pas besoin de permissions root pour l'exécution

Nécessite:
- `XDG_RUNTIME_DIR="/run/user/{UID}"` pour systemctl --user
- `loginctl enable-linger {user}` pour démarrage au boot

### Auto-login console

Configuration via override systemd (pas raspi-config):
```
/etc/systemd/system/getty@tty1.service.d/override.conf
```

### PulseAudio ACL

Le script `pulse-tcp.sh`:
- Détecte dynamiquement les IPs privées (10.x, 172.16-31.x, 192.168.x)
- Calcule les adresses réseau avec CIDR
- Configure l'ACL pour module-native-protocol-tcp
- Charge module-zeroconf-publish pour découverte réseau

## 🐛 Troubleshooting

### Ansible non installé

L'installeur installe automatiquement Ansible via apt ou pip.

### Services ne démarrent pas

```bash
# Vérifier les logs
journalctl --user -u pulseaudio -u mpd -f

# Redémarrer manuellement
systemctl --user restart pulseaudio pulse-tcp mpd
```

### Erreur "XDG_RUNTIME_DIR not set"

```bash
# Vérifier que linger est activé
loginctl show-user $USER | grep Linger

# Activer si nécessaire
sudo loginctl enable-linger $USER
```

### MPD ne trouve pas /media/USB

```bash
# Vérifier les permissions
ls -la /media/USB

# Doit être: drwxrwxr-x user audio
```

### Bluetooth ne se connecte pas

```bash
# Vérifier le service bt-agent
sudo systemctl status bt-agent

# Vérifier le PIN
cat /etc/bluetooth/pin.conf

# Réinitialiser Bluetooth
sudo systemctl restart bluetooth bt-agent
```

## 📚 Références

- [Ansible Documentation](https://docs.ansible.com/)
- [MPD Documentation](https://www.musicpd.org/doc/)
- [PulseAudio Documentation](https://www.freedesktop.org/wiki/Software/PulseAudio/)
- [Project Repository](https://github.com/b0bbywan/odios)

## 📄 Licence

Voir LICENSE dans le répertoire parent du projet.

## 🤝 Contribution

Les contributions sont bienvenues! Voir le README principal du projet pour les guidelines.
