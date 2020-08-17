#!/usr/bin/env bash

set -o pipefail -o noclobber

function cleanup() {
  verbose_print "Cleaning up..."
  if [[ ${DRY_RUN} -eq 1 ]]; then
    quiet_print "rm -f ${CERT_FILE}"
    quiet_print "rm -f ${KEY_FILE}"
  else
    /bin/rm -f "${CERT_FILE}"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      quiet_print "Could not remove source file ${CERT_FILE}"
      exit 4
    fi

    /bin/rm -f "${KEY_FILE}"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      quiet_print "Could not remove source file ${KEY_FILE}"
      exit 4
    fi
  fi
}

cleanup
