#!/usr/bin/env bash

set -o pipefail -o noclobber

function pct_exec() {
  assert_executable "PCT_BIN" "${PCT_BIN}"

  VM_ID=${1}
  shift
  assert_defined "VM_ID (\$1)" "${VM_ID}"
  verbose_print "pct_exec: VM_ID=${VM_ID}"

  COMMAND=${*}
  assert_defined "COMMAND (\$*)" "${COMMAND}"
  verbose_print "pct_exec: COMMAND=${COMMAND}"

  if [[ ${USE_SUDO} -eq 1 ]]; then
    SUDO_CMD=${SUDO_BIN}
  else
    SUDO_CMD=
  fi

  if [[ ${DRY_RUN} -eq 1 ]]; then
    quiet_print "${SUDO_CMD} ${PCT_BIN} exec ${VM_ID} -- ${COMMAND}"
  else
    ${SUDO_CMD} "${PCT_BIN}" exec "${VM_ID} -- ${COMMAND}"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        quiet_print "Failed to execute command '${SUDO_CMD} ${PCT_BIN} exec ${VM_ID} -- ${COMMAND}'"
        exit 4
    fi
  fi
}

PCT_BIN=${PCT_BIN:="/usr/sbin/pct"}
USE_SUDO=${USE_SUDO:=0}
SUDO_BIN=${SUDO_BIN:="/usr/bin/sudo"}

# Sudoers example:
# Cmnd_Alias PCT_EXEC = /usr/sbin/pct exec [[\:digit\:]][[\:digit\:]][[\:digit\:]] -- *
# certificates_manager ALL=NOPASSWD: PCT_EXEC
