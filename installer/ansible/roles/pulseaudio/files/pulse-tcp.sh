#!/bin/bash -e

MODULE_ID_FILE="/run/user/$(id --user)/pulse/rasponkyo-module-ids"

convert_cidr_to_mask() {
    local cidr_prefix=$1
    local mask=$(( 0xffffffff << (32 - cidr_prefix) ))
    echo "$(( (mask >> 24) & 0xff )).$(( (mask >> 16) & 0xff )).$(( (mask >> 8) & 0xff )).$(( mask & 0xff ))"
}

calculate_network_address() {
    local ip_address=$1
    local subnet_mask=$2

    IFS=. read -r i1 i2 i3 i4 <<< "$ip_address"
    IFS=. read -r m1 m2 m3 m4 <<< "$subnet_mask"
    echo "$((i1 & m1)).$((i2 & m2)).$((i3 & m3)).$((i4 & m4))"
}

get_ip_addresses() {
    ip -o -f inet addr show scope global | awk '{print $4}'
}

is_private_ip() {
    local ip=$1
    if [[ $ip =~ ^10\. ]] ||
       [[ $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] ||
       [[ $ip =~ ^192\.168\. ]]; then
        return 0
    fi
    return 1
}

get_acl() {
    local acl="127.0.0.1"
    while IFS= read -r cidr; do
        [[ -z "$cidr" ]] && continue
        local ip_address="${cidr%/*}"
        local cidr_prefix="${cidr#*/}"
        is_private_ip "$cidr" || continue
        local subnet_mask
        subnet_mask=$(convert_cidr_to_mask "$cidr_prefix")
        local network_address
        network_address=$(calculate_network_address "$ip_address" "$subnet_mask")
        acl="${acl};${network_address}/${cidr_prefix}"
    done < <(get_ip_addresses)
    if [[ "$acl" == "127.0.0.1" ]]; then
        logger "pulse-tcp: no private IP found, aborting"
        return 1
    fi
    echo "$acl"
}

module_is_loaded() {
    local search_key="$1"
    local expected_args="$2"
    while IFS=$'\t' read -r module_id name args; do
        if [[ -z "${expected_args}" && "${search_key}" == "${module_id}" ]] ||
           [[ "${name}" == "${search_key}" && "${args}" == "${expected_args}" ]]; then
            echo "$module_id"
            return 0
        fi
    done < <(pactl list modules short)
    return 1
}

load_module() {
    local module="$1"
    local args="$2"

    logger "Loading PulseAudio ${module} with args: ${args}"
    local module_id
    if module_id=$(module_is_loaded "${module}" "${args}"); then
        logger "${module} with args ${args} already loaded"
    else
        module_id=$(pactl load-module "${module}" "${args}")
    fi

    echo "${module_id}" >> "${MODULE_ID_FILE}"
}

check_pulseaudio_status() {
    if ! systemctl --user --quiet is-active pulseaudio.service; then
        logger "PulseAudio not running, exiting"
        exit 1
    fi
}

load_pulseaudio_modules() {
    local acl
    acl=$(get_acl) || exit 1
    load_module "module-native-protocol-tcp" "auth-ip-acl=${acl}"
    load_module "module-zeroconf-publish"
}

unload_module() {
    local module_id=$1
    if module_is_loaded "${module_id}"; then
        pactl unload-module "${module_id}"
    fi
}

unload_pulseaudio_modules() {
    logger "Unloading PulseAudio TCP and Zeroconf modules..."
    while read -r module_id; do
        unload_module "${module_id}"
    done < "$MODULE_ID_FILE"
}

remove_module_id_file() {
    rm --force "$MODULE_ID_FILE"
}

is_wired() {
    local iface name
    for iface in /sys/class/net/*; do
        name="${iface##*/}"
        [[ "$name" == "lo" || "$name" == wl* ]] && continue
        [[ "$(cat "$iface/operstate" 2>/dev/null)" == "up" ]] && return 0
    done
    return 1
}

load_modules() {
    check_pulseaudio_status
    if ! is_wired; then
        logger "pulse-tcp: wifi detected, skipping TCP/Zeroconf"
        exit 0
    fi
    load_pulseaudio_modules
}

unload_modules() {
    unload_pulseaudio_modules
    remove_module_id_file
}

case "$1" in
    start)
        load_modules
        ;;
    stop)
        unload_modules
        ;;
    *)
        echo "Usage: $0 {start|stop}"
        exit 1
        ;;
esac
