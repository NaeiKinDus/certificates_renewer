#!/usr/bin/env bash

set -o pipefail -o noclobber

function update_container() {
  verbose_print "Restarting container..."

  FULL_CMD=("${SUDO_CMD}")
  case "${USE_DOCKER_COMPOSE}" in
      0 | "no" | "false" | "n")
        DOCKER_BIN=${DOCKER_BIN:=$(command -v docker || echo "/bin/false")}
        CONTAINER_ID="${1}"
        assert_defined "CONTAINER_ID (\$1)" "${CONTAINER_ID}"

        FULL_CMD+=("${DOCKER_BIN}" container restart "${CONTAINER_ID}")
        ;;
      1 | "yes" | "true" | "y")
        COMPOSE_BIN=${COMPOSE_BIN:=$(command -v docker-compose || echo "/bin/false")}
        COMPOSE_DIR="${1}"
        COMPOSE_SVC="${2}"
        assert_defined "COMPOSE_DIR (\$1)" "${COMPOSE_DIR}"

        FULL_CMD+=("${COMPOSE_BIN}" "--project-directory" "${COMPOSE_DIR}" restart "${COMPOSE_SVC}")
        ;;
      *)
        printf "ERR\tUnsupported value for \$USE_DOCKER_COMPOSE\n"
        exit 4
        ;;
  esac
  if [[ $DRY_RUN -eq 1 ]]; then
    quiet_print "${FULL_CMD[@]}"
  else
    verbose_print "container: COMMAND=${FULL_CMD[*]}"
    # shellcheck disable=SC2068
    ${FULL_CMD[@]}
  fi
}

USE_DOCKER_COMPOSE=${USE_DOCKER_COMPOSE:=0}

# Sudoers example:
# Cmnd_Alias DOCKER_CONTAINER_RESTART = /usr/bin/docker container restart *
# Cmnd_Alias COMPOSE_CONTAINER_RESTART = /usr/local/bin/docker-compose *
