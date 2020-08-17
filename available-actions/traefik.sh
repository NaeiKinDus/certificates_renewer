#!/usr/bin/env bash

set -o pipefail -o noclobber

function update_traefik() {
    quiet_print "Running traefik update..."

    if [ ! -d "${TRAEFIK_DIR}" ]; then
	quiet_print "Destination directory ${TRAEFIK_DIR} does not exist !"
	exit 4
    fi

    # CRT update
    copy_files "${CERT_FILE}" "${TRAEFIK_DIR}/${DEST_CERT_FILENAME}"
    do_chown "${TRAEFIK_USER}" "${TRAEFIK_GROUP}" "${TRAEFIK_DIR}/${DEST_CERT_FILENAME}"

    # Private key update
    copy_files "${KEY_FILE}" "${TRAEFIK_DIR}/${DEST_KEY_FILENAME}"
    do_chown "${TRAEFIK_USER}" "${TRAEFIK_GROUP}" "${TRAEFIK_DIR}/${DEST_KEY_FILENAME}"

    verbose_print "Certificate updated, reloading Traefik..."
    if [[ $DRY_RUN -eq 1 ]]; then
	quiet_print "/bin/systemctl reload traefik.service"
    else
	/bin/systemctl restart traefik.service
	if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
	    quiet_print "Could not restart Traefik, system might be in an unstable state"
	    exit 4
	fi
    fi
}

TRAEFIK_DIR=${TRAEFIK_DIR:="/home/traefik/ssl"}
TRAEFIK_USER=${TRAEFIK_USER:="traefik"}
TRAEFIK_GROUP=${TRAEFIK_GROUP:="traefik"}

update_traefik
