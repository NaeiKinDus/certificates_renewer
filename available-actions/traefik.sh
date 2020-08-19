#!/usr/bin/env bash

set -o pipefail -o noclobber

function update_traefik() {
  quiet_print "Running traefik update..."

  if [ ! -d "${TRAEFIK_DIR}" ]; then
    quiet_print "Destination directory ${TRAEFIK_DIR} does not exist !"
    exit 4
  fi

  if [[ ${USE_SUDO} -eq 1 ]]; then
    SUDO_CMD=${SUDO_BIN}
  else
    SUDO_CMD=
  fi

  # CRT update
  copy_files "${CERT_FILE}" "${TRAEFIK_DIR}/${DEST_CERT_FILENAME}"
  do_chown "${TRAEFIK_USER}" "${TRAEFIK_GROUP}" "${TRAEFIK_DIR}/${DEST_CERT_FILENAME}"

  # Private key update
  copy_files "${KEY_FILE}" "${TRAEFIK_DIR}/${DEST_KEY_FILENAME}"
  do_chown "${TRAEFIK_USER}" "${TRAEFIK_GROUP}" "${TRAEFIK_DIR}/${DEST_KEY_FILENAME}"

  verbose_print "Certificate updated, reloading Traefik..."
  if [[ $DRY_RUN -eq 1 ]]; then
    quiet_print "${SUDO_CMD} /bin/systemctl restart traefik.service"
  else
    ${SUDO_CMD} /bin/systemctl restart traefik.service
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      quiet_print "Could not restart Traefik, system might be in an unstable state"
      exit 4
    fi
  fi
}

TRAEFIK_DIR=${TRAEFIK_DIR:="/home/traefik/ssl"}
TRAEFIK_USER=${TRAEFIK_USER:="traefik"}
TRAEFIK_GROUP=${TRAEFIK_GROUP:="traefik"}
USE_SUDO=${USE_SUDO:=0}
SUDO_BIN=${SUDO_BIN:="/usr/bin/sudo"}

# Sudoers example:
# Cmnd_Alias CP_TRAEFIK = /bin/cp /opt/certificates_manager/new_certificates/domain.crt /home/traefik/ssl/domain.crt, /bin/cp /opt/certificates_manager/new_certificates/domain.key /home/traefik/ssl/domain.key
# Cmnd_Alias CHMOD_TRAEFIK = /bin/chmod 600 /home/traefik/ssl/domain.crt, /bin/chmod 600 /home/traefik/ssl/domain.key
# Cmnd_Alias CHOWN_TRAEFIK = /bin/chown traefik\:traefik /home/traefik/ssl/domain.crt, /bin/chown traefik\:traefik /home/traefik/ssl/domain.key
# Cmnd_Alias RESTART_TRAEFIK = /bin/systemctl restart traefik.service
# certificates_manager ALL=NOPASSWD: CP_TRAEFIK, CHMOD_TRAEFIK, CHOWN_TRAEFIK, RESTART_TRAEFIK
