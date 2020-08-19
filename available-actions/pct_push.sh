#!/usr/bin/env bash

set -o pipefail -o noclobber

function pct_push() {
  assert_executable "PCT_BIN" "${PCT_BIN}"

  VM_ID=${1}
  assert_defined "VM_ID (\$1)" "${VM_ID}"
  verbose_print "pct_push: VM_ID=${VM_ID}"

  SRC_FILE=${2}
  assert_defined "SRC_FILE (\$2)" "${SRC_FILE}"
  verbose_print "pct_push: SRC_FILE=${SRC_FILE}"

  DST_FILE=${3}
  assert_defined "DST_FILE (\$3)" "${DST_FILE}"
  verbose_print "pct_push: DST_FILE=${DST_FILE}"

  if [[ $USE_SUDO -eq 1 ]]; then
    SUDO_CMD=${SUDO_BIN}
  else
    SUDO_CMD=
  fi

  if [[ ${DRY_RUN} -eq 1 ]]; then
    quiet_print "${SUDO_CMD} ${PCT_BIN} push ${VM_ID} ${SRC_FILE} ${DST_FILE}"
  else
    ${SUDO_CMD} "${PCT_BIN}" push "${VM_ID}" "${SRC_FILE}" "${DST_FILE}"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        quiet_print "Failed to execute command '${SUDO_CMD} ${PCT_BIN} push ${VM_ID} ${SRC_FILE} ${DST_FILE}'"
        exit 4
    fi
  fi
}

PCT_BIN=${PCT_BIN:="/usr/sbin/pct"}
USE_SUDO=${USE_SUDO:=0}
SUDO_BIN=${SUDO_BIN:="/usr/bin/sudo"}

# Sudoers example:
# Cmnd_Alias PCT_PUSH = /usr/sbin/pct push [[\:digit\:]][[\:digit\:]][[\:digit\:]] /opt/cert_manager/new_certificates/*
# certificates_manager ALL=NOPASSWD: PCT_PUSH
