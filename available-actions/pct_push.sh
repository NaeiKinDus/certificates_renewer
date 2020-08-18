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

  if [[ ${DRY_RUN} -eq 1 ]]; then
    quiet_print "${PCT_BIN} ${VM_ID} ${SRC_FILE} ${DST_FILE}"
  else
    ${PCT_BIN} "${VM_ID}" "${SRC_FILE}" "${DST_FILE}"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        quiet_print "Failed to execute command '${PCT_BIN} ${SRC_FILE} ${DST_FILE}'"
        exit 4
    fi
  fi
}

PCT_BIN=${PCT_BIN:="/usr/sbin/pct"}
