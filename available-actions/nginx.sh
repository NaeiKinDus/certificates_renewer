#!/usr/bin/env bash

set -o pipefail -o noclobber

function update_nginx() {
  verbose_print "Running Nginx update..."

  if [ ! -d "${NGINX_DIR}" ]; then
    quiet_print "Destination directory ${NGINX_DIR} does not exist !"
    exit 4
  fi

  if [[ ${USE_SUDO} -eq 1 ]]; then
    SUDO_CMD=${SUDO_BIN}
  else
    SUDO_CMD=
  fi

  # CRT update
  TARGET_CERT="${NGINX_DIR}/${DEST_CERT_FILENAME}"
  copy_files "${CERT_FILE}" "${TARGET_CERT}"
  do_chown "${NGINX_USER}" "${NGINX_GROUP}" "${TARGET_CERT}"

  # Private key update
  TARGET_KEY="${NGINX_DIR}/${DEST_KEY_FILENAME}"
  copy_files "${KEY_FILE}" "${TARGET_KEY}"
  do_chown "${NGINX_USER}" "${NGINX_GROUP}" "${TARGET_KEY}"

  do_chmod 600 "${TARGET_CERT}" "${TARGET_KEY}"

  # Reloading Nginx
  verbose_print "Certificate updated, reloading Nginx..."
  if [[ $DRY_RUN -eq 1 ]]; then
    quiet_print "${SUDO_CMD} /bin/systemctl restart nginx.service"
  else
    ${SUDO_CMD} /bin/systemctl restart nginx.service
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      quiet_print "Could not restart nginx, system might be in an unstable state"
      exit 4
    fi
  fi
  verbose_print "Success !"
}

NGINX_USER=${NGINX_USER:="www-data"}
NGINX_GROUP=${NGINX_GROUP:="www-data"}
NGINX_DIR=${NGINX_DIR:="/etc/nginx/ssl"}
USE_SUDO=${USE_SUDO:=0}
SUDO_BIN=${SUDO_BIN:="/usr/bin/sudo"}

# Sudoers example:
# Cmnd_Alias CP_NGINX = /bin/cp /opt/certificates_manager/new_certificates/domain.crt /etc/nginx/ssl/domain.crt, /bin/cp /opt/certificates_manager/new_certificates/domain.key /etc/nginx/ssl/domain.key
# Cmnd_Alias CHMOD_NGINX = /bin/chmod 600 /etc/nginx/ssl/domain.crt, /bin/chmod 600 /etc/nginx/ssl/domain.key
# Cmnd_Alias CHOWN_NGINX = /bin/chown www-data\:www-data /etc/nginx/ssl/domain.crt, /bin/chown www-data\:www-data /etc/nginx/ssl/domain.key
# Cmnd_Alias RESTART_NGINX = /bin/systemctl restart nginx.service
#
# certificates_manager ALL=NOPASSWD: CP_NGINX, CHMOD_NGINX, CHOWN_NGINX, RESTART_NGINX
