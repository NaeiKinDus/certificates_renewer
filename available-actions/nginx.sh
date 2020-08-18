#!/usr/bin/env bash

set -o pipefail -o noclobber

function update_nginx() {
  verbose_print "Running Nginx update..."

  if [ ! -d "${NGINX_DIR}" ]; then
    quiet_print "Destination directory ${NGINX_DIR} does not exist !"
    exit 4
  fi

  # CRT update
  copy_files "${CERT_FILE}" "${NGINX_DIR}/${DEST_CERT_FILENAME}"
  do_chown "${NGINX_USER}" "${NGINX_GROUP}" "${NGINX_DIR}/${DEST_CERT_FILENAME}"

  # Private key update
  copy_files "${KEY_FILE}" "${NGINX_DIR}/${DEST_KEY_FILENAME}"
  do_chown "${NGINX_USER}" "${NGINX_GROUP}" "${NGINX_DIR}/${DEST_KEY_FILENAME}"

  # Reloading Nginx
  verbose_print "Certificate updated, reloading Nginx..."
  if [[ $DRY_RUN -eq 1 ]]; then
    quiet_print "/bin/systemctl restart nginx.service"
  else
    /bin/systemctl restart nginx.service
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      quiet_print "Could not reload nginx, system might be in an unstable state"
      exit 4
    fi
  fi
  verbose_print "Success !"
}

NGINX_USER=${NGINX_USER:="www-data"}
NGINX_GROUP=${NGINX_GROUP:="www-data"}
NGINX_DIR=${NGINX_DIR:="/etc/nginx/ssl"}
