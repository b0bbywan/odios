# Plan d'implémentation: Installeur Ansible "curl | bash" pour système audio multimédia

## Vue d'ensemble

Convertir le stage pi-gen audio en installeur Ansible autonome avec script bootstrap, permettant une installation via:
```bash
curl -fsSL https://example.com/install.sh | bash
```

## Décisions d'architecture

### 1. Type d'installeur
- **Choix**: Ansible avec bootstrap script
- **Raison**: Structure organisée, réutilisable, mais nécessite installation d'Ansible
- **Approche**: Script bash installe Ansible → extrait playbook → exécute installation

### 2. Configuration
- **Choix**: Prompts interactifs
- **Raison**: Meilleure UX pour configuration (hostname, PIN Bluetooth, version Spotifyd)
- **Fallback**: Support variables d'environnement pour CI/automation

### 3. Compatibilité OS
- **Choix**: Debian/Ubuntu générique
- **Raison**: Plus large compatibilité, pas limité au Raspberry Pi
- **Conséquences**:
  - Pas de dépendance à raspi-config
  - Détection d'architecture pour binaires (ARM vs x86_64)
  - Configuration getty manuelle pour auto-login

### 4. Modularité des composants
- **Choix**: Core + optionnels
- **Core obligatoire**:
  - PulseAudio (avec TCP et Zeroconf)
  - Bluetooth audio
  - Music Player Daemon (MPD)
- **Optionnels**:
  - Spotifyd (Spotify Connect)
  - Shairport Sync (AirPlay)
  - Snapcast client (multi-room audio)
  - UPnP/DLNA renderer (upmpdcli)
  - MPD disc player (CD/DVD)

### 5. Structure du playbook
- **Choix**: Playbook embarqué en base64 dans le bootstrap
- **Raison**: Installation en une seule commande, pas de dépendance git
- **Structure**: Roles Ansible (un par composant) pour réutilisabilité

## Structure du projet

```
/home/user/odios/
├── stage-audio/              # Stage pi-gen original (conservé pour référence)
├── installer/                # Nouveau répertoire installeur
│   ├── README.md             # Documentation d'installation
│   ├── build.sh              # Script de build: génère install.sh avec playbook embarqué
│   ├── bootstrap.sh          # Script bootstrap (template pour build.sh)
│   │
│   └── ansible/              # Composants Ansible
│       ├── playbook.yml      # Playbook principal
│       ├── inventory/
│       │   └── localhost.yml # Inventory localhost
│       ├── group_vars/
│       │   └── all.yml       # Variables par défaut
│       │
│       └── roles/
│           ├── common/                    # Pré-requis communs
│           │   ├── tasks/main.yml
│           │   ├── vars/main.yml
│           │   └── handlers/main.yml
│           │
│           ├── pulseaudio/                # [CORE] PulseAudio + TCP + Zeroconf
│           │   ├── tasks/main.yml
│           │   ├── files/
│           │   │   └── pulse-tcp.sh       # Script ACL dynamique (copié tel quel)
│           │   ├── templates/
│           │   │   └── pulse-tcp.service.j2
│           │   └── handlers/main.yml
│           │
│           ├── bluetooth/                 # [CORE] Bluetooth audio
│           │   ├── tasks/main.yml
│           │   ├── files/
│           │   │   ├── success.wav        # Son de connexion BT
│           │   │   ├── bt-connection.sh   # Script notification
│           │   │   └── 99-bluetooth.rules # Règle udev
│           │   ├── templates/
│           │   │   ├── bluetooth-main.conf.j2
│           │   │   ├── bluetooth-pin.conf.j2
│           │   │   └── bt-agent.service.j2
│           │   └── handlers/main.yml
│           │
│           ├── mpd/                       # [CORE] Music Player Daemon
│           │   ├── tasks/main.yml
│           │   ├── templates/
│           │   │   └── mpd.conf.j2        # Config complète (pas de patch)
│           │   └── handlers/main.yml
│           │
│           ├── spotifyd/                  # [OPTIONNEL] Spotify Connect
│           │   ├── tasks/main.yml
│           │   ├── vars/main.yml          # Mapping architecture → binaire
│           │   ├── templates/
│           │   │   ├── spotifyd.conf.j2
│           │   │   ├── spotifyd.service.j2
│           │   │   └── asound.rc.j2
│           │   └── handlers/main.yml
│           │
│           ├── shairport_sync/            # [OPTIONNEL] AirPlay receiver
│           │   ├── tasks/main.yml
│           │   ├── templates/
│           │   │   ├── shairport-sync.conf.j2
│           │   │   ├── shairport-sync.service.j2
│           │   │   └── shairport-dbus-policies.conf.j2
│           │   └── handlers/main.yml
│           │
│           ├── snapclient/                # [OPTIONNEL] Snapcast client
│           │   ├── tasks/main.yml
│           │   ├── templates/
│           │   │   └── snapclient.default.j2
│           │   └── handlers/main.yml
│           │
│           ├── upmpdcli/                  # [OPTIONNEL] UPnP/DLNA renderer
│           │   ├── tasks/main.yml
│           │   ├── templates/
│           │   │   ├── upmpdcli.conf.j2
│           │   │   └── upmpdcli.sources.j2
│           │   └── handlers/main.yml
│           │
│           └── mpd_discplayer/            # [OPTIONNEL] CD/DVD player
│               ├── tasks/main.yml
│               ├── files/
│               │   └── .mpdignore
│               ├── templates/
│               │   ├── mpd-discplayer.yaml.j2
│               │   └── bobbywan.sources.j2
│               └── handlers/main.yml
```

## Flux d'exécution du bootstrap

```
1. Affichage bannière + version
2. Prompts interactifs:
   - Hostname pour advertising (défaut: $(hostname))
   - PIN Bluetooth (défaut: 0000)
   - User cible (défaut: $USER)
   - Composants optionnels (checkboxes):
     [ ] Spotifyd (Spotify Connect)
     [ ] Shairport Sync (AirPlay)
     [ ] Snapcast client
     [ ] UPnP/DLNA renderer
     [ ] MPD disc player
3. Pre-flight checks:
   - OS: Debian/Ubuntu via /etc/os-release
   - Architecture: uname -m (armv6l, armv7l, aarch64, x86_64)
   - Sudo access
   - Connectivité réseau
   - Espace disque (min 500MB)
   - Systemd disponible
4. Installation Ansible (si absent):
   - apt-get install ansible (préféré)
   - pip3 install ansible (fallback)
   - Vérification version ≥ 2.9
5. Extraction playbook:
   - Création répertoire temporaire
   - Décodage base64 → tar.gz
   - Extraction playbook complet
6. Exécution Ansible:
   - Génération extra-vars JSON depuis prompts
   - ansible-playbook avec inventory localhost
   - Stream output vers user
7. Cleanup:
   - Suppression répertoire temporaire
   - (Optionnel) Désinstallation Ansible si installé par script
8. Message de succès + instructions de test
```

## Variables d'installation

### Variables collectées (prompts)
- `target_hostname`: Nom d'hôte pour advertising services (ex: "raspiaudio")
- `target_user`: User système pour services (ex: "pi" ou $USER)
- `bluetooth_pin`: Code PIN Bluetooth (ex: "0000")
- `spotifyd_version`: Version Spotifyd (ex: "0.3.5", auto-détecté depuis GitHub API)

### Variables optionnelles (composants)
- `install_spotifyd`: bool
- `install_shairport_sync`: bool
- `install_snapclient`: bool
- `install_upmpdcli`: bool
- `install_mpd_discplayer`: bool

### Variables dérivées (détection)
- `target_user_uid`: UID de target_user (pour services user et /run/user/{uid})
- `system_arch`: Architecture système (ansible_architecture)
- `spotifyd_arch_suffix`: Suffixe binaire Spotifyd selon arch
  - armv6l → "linux-armv6-slim"
  - armv7l → "linux-armhf-slim"
  - aarch64 → "linux-arm64-slim"
  - x86_64 → "linux-full"

### Variables OS
- `os_id`: Debian, Ubuntu, Raspbian (depuis /etc/os-release)
- `os_version_id`: Version majeure (10, 11, 12 pour Debian; 20.04, 22.04 pour Ubuntu)

## Tâches critiques d'implémentation

### Phase 1: Structure et squelette (2-3h)
- [x] Créer structure répertoires installer/
- [ ] Créer inventory localhost.yml
- [ ] Créer group_vars/all.yml avec variables par défaut
- [ ] Créer playbook.yml squelette avec pre_tasks/post_tasks
- [ ] Créer squelette de tous les roles (tasks/main.yml vides)

### Phase 2: Role common (1h)
- [ ] Détection user UID
- [ ] Création répertoire /media/USB (owner target_user, group audio)
- [ ] Configuration getty auto-login (sans raspi-config)
- [ ] Installation paquets de base (python3-pip, etc.)
- [ ] Enable linger pour target_user (loginctl enable-linger)

### Phase 3: Role PulseAudio [CORE] (2h)
- [ ] Installation paquets: pulseaudio, pulseaudio-module-zeroconf, pulseaudio-module-bluetooth
- [ ] Copie pulse-tcp.sh vers /usr/local/bin/ (mode 755)
- [ ] Template pulse-tcp.service.j2 → ~/.config/systemd/user/pulse-tcp.service
- [ ] Enable user services: pulseaudio.service, pulse-tcp.service
- [ ] Handler: restart pulseaudio

### Phase 4: Role Bluetooth [CORE] (2h)
- [ ] Installation paquets: bluez, bluez-tools
- [ ] Template bluetooth-main.conf.j2 → /etc/bluetooth/main.conf (avec target_hostname)
- [ ] Template bluetooth-pin.conf.j2 → /etc/bluetooth/pin.conf (avec bluetooth_pin, mode 600)
- [ ] Template bt-agent.service.j2 → /etc/systemd/system/bt-agent.service
- [ ] Copie bt-connection.sh → /usr/local/bin/ (mode 755)
- [ ] Copie success.wav → /usr/local/share/sounds/ (mode 644)
- [ ] Copie 99-bluetooth.rules → /etc/udev/rules.d/
- [ ] Ajouter target_user au groupe bluetooth
- [ ] Enable system service: bt-agent.service
- [ ] Handler: restart bluetooth, reload udev

### Phase 5: Role MPD [CORE] (2-3h)
- [ ] Installation paquets: mpd, mpc
- [ ] Désactivation system service mpd (enable user service à la place)
- [ ] Création répertoires:
  - ~/.config/mpd/ (mode 700)
  - ~/.local/share/mpd/{playlists,cache} (mode 700)
- [ ] Template mpd.conf.j2 → ~/.config/mpd/mpd.conf (attention: UID dynamique pour socket)
- [ ] Création state file vide (force: no pour idempotence)
- [ ] Enable user service: mpd.service
- [ ] Handler: restart mpd

### Phase 6: Role Spotifyd [OPTIONNEL] (2-3h)
- [ ] Condition: when install_spotifyd == true
- [ ] Détection architecture (vars/main.yml)
- [ ] Téléchargement binaire depuis GitHub releases (get_url avec URL dynamique)
- [ ] Extraction vers /usr/local/bin/spotifyd (mode 755)
- [ ] Template asound.rc.j2 → /etc/asound.rc (redirection vers PulseAudio)
- [ ] Création ~/.config/spotifyd/ (mode 700)
- [ ] Template spotifyd.conf.j2 → ~/.config/spotifyd/spotifyd.conf (mode 600)
- [ ] Template spotifyd.service.j2 → ~/.config/systemd/user/spotifyd.service
- [ ] Enable user service: spotifyd.service
- [ ] Handler: restart spotifyd

### Phase 7: Role Shairport Sync [OPTIONNEL] (2h)
- [ ] Condition: when install_shairport_sync == true
- [ ] Installation paquet: shairport-sync
- [ ] Template shairport-sync.conf.j2 → /etc/shairport-sync.conf (backend pa, server 127.0.0.1)
- [ ] Template DBus policies pour org.gnome.ShairportSync
- [ ] Copie systemd user service (ou utiliser celui du paquet?)
- [ ] Enable user service: shairport-sync.service
- [ ] Handler: restart shairport-sync

### Phase 8: Role Snapclient [OPTIONNEL] (1h)
- [ ] Condition: when install_snapclient == true
- [ ] Installation paquet: snapclient
- [ ] Template snapclient.default.j2 → /etc/default/snapclient (SNAPCLIENT_OPTS="--player pulse")
- [ ] Enable system ou user service (vérifier lequel)
- [ ] Handler: restart snapclient

### Phase 9: Role UPnP/DLNA [OPTIONNEL] (2h)
- [ ] Condition: when install_upmpdcli == true
- [ ] Téléchargement clé GPG lesbonscomptes.com
- [ ] Ajout repository (template .sources pour DEB822)
- [ ] Update apt cache
- [ ] Installation paquet: upmpdcli
- [ ] Template upmpdcli.conf.j2 → /etc/upmpdcli.conf (friendly name avec target_hostname)
- [ ] Enable system service: upmpdcli.service
- [ ] Handler: restart upmpdcli

### Phase 10: Role MPD DiscPlayer [OPTIONNEL] (2h)
- [ ] Condition: when install_mpd_discplayer == true
- [ ] Téléchargement clé GPG bobbywan.me
- [ ] Ajout repository apt.bobbywan.me
- [ ] Installation paquet: mpd-discplayer
- [ ] Création ~/.config/mpd-discplayer/ (mode 700)
- [ ] Template mpd-discplayer.yaml.j2 → ~/.config/mpd-discplayer/config.yaml
- [ ] Copie .mpdignore → /media/USB/.mpdignore
- [ ] Enable user service: mpd-discplayer.service
- [ ] Handler: restart mpd-discplayer

### Phase 11: Bootstrap script (3-4h)
- [ ] Fonction: display_banner()
- [ ] Fonction: prompt_for_config() avec validation
  - Hostname (validation: alphanumeric + hyphens)
  - PIN Bluetooth (validation: 4-16 digits)
  - User (validation: user exists)
  - Composants optionnels (checkboxes interactifs)
- [ ] Fonction: preflight_checks()
  - Check OS (Debian/Ubuntu/Raspbian)
  - Check architecture (supportée)
  - Check sudo
  - Check network (ping 8.8.8.8)
  - Check disk space (df /tmp > 500MB)
  - Check systemd
- [ ] Fonction: install_ansible()
  - Détection ansible
  - Installation apt ou pip
  - Vérification version
- [ ] Fonction: extract_playbook()
  - mktemp -d
  - base64 decode + tar extract
- [ ] Fonction: run_playbook()
  - Génération JSON extra-vars
  - ansible-playbook localhost inventory
- [ ] Fonction: cleanup()
- [ ] Fonction: main() orchestration

### Phase 12: Build system (1-2h)
- [ ] Script build.sh:
  - Tar+gzip ansible/
  - Base64 encode
  - Inject dans bootstrap.sh template
  - Générer install.sh final
  - Calculer checksum SHA256
- [ ] Test: génération + extraction
- [ ] Vérification taille fichier (<5MB recommandé)

### Phase 13: Templates Jinja2 (4-5h)
Convertir tous les patches en templates:
- [ ] mpd.conf.j2 (complet, pas de patch)
- [ ] shairport-sync.conf.j2 (backend pa, server 127.0.0.1)
- [ ] upmpdcli.conf.j2 (friendly name)
- [ ] spotifyd.conf.j2 (device_name, bitrate)
- [ ] mpd-discplayer.yaml.j2 (socket path avec UID)
- [ ] bluetooth-main.conf.j2 (Name = hostname)
- [ ] bluetooth-pin.conf.j2 (PIN code)
- [ ] pulse-tcp.service.j2
- [ ] bt-agent.service.j2
- [ ] spotifyd.service.j2
- [ ] shairport-sync.service.j2 (si custom)
- [ ] asound.rc.j2 (ALSA → PulseAudio)
- [ ] snapclient.default.j2

### Phase 14: Tests (3-4h)
- [ ] Test playbook seul (ansible-playbook direct)
- [ ] Test bootstrap complet (bash install.sh)
- [ ] Test idempotence (run 2x, vérifier "ok" vs "changed")
- [ ] Test architecture ARM (si dispo)
- [ ] Test architecture x86_64
- [ ] Test composants optionnels (installation partielle)
- [ ] Test services démarrent correctement
- [ ] Test connectivité Bluetooth
- [ ] Test streaming PulseAudio
- [ ] Test MPD lecture

### Phase 15: Documentation (1-2h)
- [ ] README.md installer/:
  - Installation simple: curl | bash
  - Installation review-first: curl -o + bash
  - Variables d'environnement pour automation
  - Prérequis système
  - Architecture supportées
  - Composants installés
  - Troubleshooting
- [ ] README.md projet:
  - Mettre à jour avec lien vers installer
  - Documenter build process

## Points d'attention critiques

### 1. UID dynamique vs hardcodé
**Problème**: Le stage pi-gen utilise UID 1000 en dur (ex: `/run/user/1000/mpd.socket`)
**Solution**:
```yaml
- name: Get target user UID
  command: "id -u {{ target_user }}"
  register: user_uid
  changed_when: false

- name: Set UID fact
  set_fact:
    target_user_uid: "{{ user_uid.stdout }}"
```
Puis utiliser `{{ target_user_uid }}` dans les templates.

### 2. Services systemd user
**Problème**: Nécessite XDG_RUNTIME_DIR pour systemctl --user
**Solution**:
```yaml
- name: Enable user service
  become: yes
  become_user: "{{ target_user }}"
  systemd:
    name: mpd.service
    enabled: yes
    scope: user
    daemon_reload: yes
  environment:
    XDG_RUNTIME_DIR: "/run/user/{{ target_user_uid }}"
```

### 3. Architecture multi-plateforme Spotifyd
**Problème**: Binaire différent selon architecture
**Solution**: Mapping dans vars/main.yml:
```yaml
spotifyd_arch_map:
  armv6l: "linux-armv6-slim"
  armv7l: "linux-armhf-slim"
  aarch64: "linux-arm64-slim"
  x86_64: "linux-full"
```

### 4. Repositories APT custom
**Problème**: Format DEB822 (.sources) vs legacy
**Solution**: Utiliser format .sources (DEB822) compatible Debian ≥12, Ubuntu ≥22.04:
```jinja
Types: deb
URIs: https://www.lesbonscomptes.com/upmpdcli/downloads/{{ ansible_distribution|lower }}/
Suites: {{ ansible_distribution_release }}
Components: main
Signed-By: /usr/share/keyrings/lesbonscomptes.gpg
```

### 5. Auto-login sans raspi-config
**Problème**: raspi-config n'existe pas sur Debian/Ubuntu standard
**Solution**: Override getty@tty1.service:
```yaml
- name: Configure getty auto-login
  copy:
    dest: /etc/systemd/system/getty@tty1.service.d/override.conf
    content: |
      [Service]
      ExecStart=
      ExecStart=-/sbin/agetty --autologin {{ target_user }} --noclear %I $TERM
```

### 6. PulseAudio ACL script
**Problème**: pulse-tcp.sh est complexe avec calculs réseau
**Solution**: NE PAS template, copier tel quel. Le script est auto-suffisant.

### 7. Idempotence
**Clés**:
- Utiliser modules Ansible déclaratifs (file, template, systemd)
- `creates:` pour downloads
- `force: no` pour fichiers initiaux (state file MPD)
- Handlers pour restarts (pas de restart systématique)

## Estimation temps total

- **Phase 1-2 (Structure + Common)**: 3-4h
- **Phase 3-5 (Roles CORE)**: 6-8h
- **Phase 6-10 (Roles OPTIONNELS)**: 9-11h
- **Phase 11-12 (Bootstrap + Build)**: 4-6h
- **Phase 13 (Templates)**: 4-5h
- **Phase 14 (Tests)**: 3-4h
- **Phase 15 (Documentation)**: 1-2h

**TOTAL ESTIMÉ**: 30-40h de développement

## Livrables finaux

1. **installer/install.sh**: Script d'installation autonome (curl | bash ready)
2. **installer/ansible/**: Playbook Ansible complet et réutilisable
3. **installer/build.sh**: Script de build pour régénérer install.sh
4. **installer/README.md**: Documentation d'installation
5. **Tests**: Suite de tests validant tous les composants
6. **Documentation**: Guide d'utilisation et troubleshooting

## Commandes d'installation finales

### Installation simple (production)
```bash
curl -fsSL https://example.com/install.sh | bash
```

### Installation avec review (sécurité)
```bash
curl -fsSL https://example.com/install.sh -o install.sh
less install.sh  # Review du script
chmod +x install.sh
./install.sh
```

### Installation automatisée (CI/CD)
```bash
export TARGET_HOSTNAME="raspiaudio"
export TARGET_USER="pi"
export BLUETOOTH_PIN="1234"
export SPOTIFYD_VERSION="0.3.5"
export INSTALL_SPOTIFYD="true"
export INSTALL_SHAIRPORT_SYNC="true"
export INSTALL_SNAPCLIENT="false"
export INSTALL_UPMPDCLI="true"
export INSTALL_MPD_DISCPLAYER="false"
curl -fsSL https://example.com/install.sh | bash -s -- --non-interactive
```

## Prochaines étapes

1. Validation de ce plan par l'utilisateur
2. Création de la branche Git pour développement
3. Implémentation phase par phase
4. Tests continus à chaque phase
5. Release v1.0.0 avec installer fonctionnel
