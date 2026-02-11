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

filter_private_ips() {
    local ip_info=("$@")
    local private_ips=()

    for ip in "${ip_info[@]}"; do
        if is_private_ip "$ip"; then
            private_ips+=("$ip")
        fi
    done
    echo "${private_ips[@]}"
}

build_acl_string() {
    local ip_info=("$@")
    local network_addresses=("127.0.0.1")

    for ip in "${ip_info[@]}"; do
        ip_address=$(echo "$ip" | cut -d/ -f1)
        cidr_prefix=$(echo "$ip" | cut -d/ -f2)
        subnet_mask=$(convert_cidr_to_mask "$cidr_prefix")
        network_address=$(calculate_network_address "$ip_address" "$subnet_mask")
        network_addresses+=("$network_address/$cidr_prefix")
    done
    echo "${network_addresses[*]}" | tr ' ' ';'
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
    local ip_info
    ip_info=$(get_ip_addresses)
    local private_ips
    private_ips=$(filter_private_ips "$ip_info")
    build_acl_string "$private_ips"
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
    load_module "module-native-protocol-tcp" "auth-ip-acl=$(get_acl)"
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

load_modules() {
    check_pulseaudio_status
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