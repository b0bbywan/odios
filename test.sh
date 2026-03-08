#!/bin/bash
set -e

CONTAINER_NAME="odios-test"
IMAGE_NAME="odios-test"

case "$1" in
  shell|rerun|clean)
    ACTION="$1"
    shift
    ;;
  --help|-h)
    echo "Usage: $0 [test|shell|rerun|clean] [ansible args...]"
    echo ""
    echo "  test   - Build + start + run playbook (default)"
    echo "  shell  - Shell into running container"
    echo "  rerun  - Re-run playbook without rebuild"
    echo "  clean  - Remove container"
    exit 0
    ;;
  *)
    ACTION="test"
    ;;
esac

case "${ACTION}" in
  test)
    echo "=== Building image ==="
    docker build -t "${IMAGE_NAME}" -f Dockerfile.test .

    echo "=== Starting container with systemd ==="
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    docker run -d \
      --name "${CONTAINER_NAME}" \
      --privileged \
      --cgroupns=host \
      --user root \
      -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
      "${IMAGE_NAME}"

    echo "=== Waiting for systemd ==="
    sleep 3

    echo "=== Running playbook ==="
    docker exec -u odios "${CONTAINER_NAME}" \
      ansible-playbook -v -i inventory/localhost.yml \
        /opt/odios/ansible/playbook.yml \
        -e "install_shairport_sync=true" \
        -e "install_upmpdcli=true" \
        -e "install_snapclient=true" \
        -e "install_mpd_discplayer=true" \
        "$@"

    echo "=== Done ==="
    ;;

  shell)
    docker exec -it -u odios "${CONTAINER_NAME}" bash
    ;;

  rerun)
    echo "=== Re-running playbook ==="
    docker exec -u odios "${CONTAINER_NAME}" \
      ansible-playbook -i inventory/localhost.yml /opt/odios/ansible/playbook.yml \
        -e "install_shairport_sync=true" \
        -e "install_upmpdcli=true" \
        -e "install_snapclient=true" \
        -e "install_mpd_discplayer=true" \
        "$@"
    ;;

  clean)
    docker rm -f "${CONTAINER_NAME}" 2>/dev/null || true
    echo "Cleaned."
    ;;
esac

