#!/usr/bin/env bash

set -o pipefail -o noclobber

function usage() {
    cat <<EOF
USAGE
\$> $0 dir

ARGUMENTS
dir: path to where the lego certificates reside

OPTIONS
-h/--help: show this menu
-q/--quiet: no output, any error will be fatal
-v/--verbose: show more debug messages
-e/--env: specify an environment file
-m/--email <mail_address>: email to sent a report when the script is finished
-s/--domain <domain_name>: use a specific domain if multiple keys are present
-d/--dry-run: print the commands instead of running them
-c/--cert-name <filename>: name used for the certificate file in destination (must include file extension)
-k/--key-name <filename>: name used for the private key file in destination (must include file extension)
--nginx-dir <dir>: directory where the certificate files will be stored for nginx
--nginx-user <account_name>: user owning the nginx / website files (usually www-data)
--nginx-group <group_name>: group owning the nginx / website files (usually www-data)
--traefik-dir: directory where the certificate files will be stored for traefik
--traefik-user <account_name>: user owning the configuration files for traefik (usually traefik)
--traefik-group <group_name>: group owning the configuration files for traefik (usually traefik)
EOF
}

source ./common.sh

function cleanup() {
  verbose_print "Cleaning up..."
  verbose_print "rm -f ${CERT_FILE}"
  verbose_print "rm -f ${KEY_FILE}"
}

#####################################
# Software related update functions #
#####################################
function update_nginx() {
    quiet_print "Running Nginx update..."

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
	quiet_print "/bin/systemctl reload nginx.service"
    else
	/bin/systemctl reload nginx.service
	if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
	    quiet_print "Could not reload nginx, system might be in an unstable state"
	    exit 4
	fi
    fi
    verbose_print "Success !"
}

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

#####################
# Shell script entry #
#####################
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo -e "Getopt not available, please install linux-utils or similar package."
    exit 1
fi

OPTIONS=hvm:e:ds:c:k:q
LONGOPTS=help,verbose,email:,env:,dry-run,domain:,cert-name:,key-name:,quiet,nginx-dir:,traefik-dir:,nginx-user:,nginx-group:,traefik-user:,traefik-group:

! PARSED=$(getopt --options=${OPTIONS} --longoptions=${LONGOPTS} --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    exit 2
fi

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

eval set -- "${PARSED}"
# Defaults
EMAIL_CONTACT=
VERBOSE=${VERBOSE:=0}
DRY_RUN=${DRY_RUN:=0}
MATCH_DOMAIN=${MATCH_DOMAIN:=""}
DST_CERT_NAME=${DST_CERT_NAME:=""}
DST_KEY_NAME=${DST_KEY_NAME:=""}
NO_OUTPUT=${NO_OUTPUT:=0}
NGINX_DIR=${NGINX_DIR:="/etc/nginx/ssl"}
TRAEFIK_DIR=${TRAEFIK_DIR:="/home/traefik/ssl"}
NGINX_USER=${NGINX_USER:="www-data"}
NGINX_GROUP=${NGINX_GROUP:="www-data"}
TRAEFIK_USER=${TRAEFIK_USER:="traefik"}
TRAEFIK_GROUP=${TRAEFIK_GROUP:="traefik"}
ENV_FILE=${ENV_FILE:=".env"}

export DRY_RUN
export EMAIL_CONTACT
export NO_OUTPUT
export VERBOSE

# Options
while true; do
    case "$1" in
	-h|--help)
	    usage
	    exit 0
	    ;;
	-s|--domain)
	    MATCH_DOMAIN="$2"
	    shift 2
	    ;;
	-v|--verbose)
	    VERBOSE=1
	    shift
	    ;;
	-e|--env)
	    ENV_FILE="$2"
      shift 2
	    ;;
	-m|--email)
	    EMAIL_CONTACT="$2"
	    shift 2
	    ;;
	-d|--dry-run)
	    DRY_RUN=1
	    shift
	    ;;
	-c|--cert-name)
	    DST_CERT_NAME="$2"
	    shift 2
	    ;;
	-k|--key-name)
	    DST_KEY_NAME="$2"
	    shift 2
	    ;;
	-q|--quiet)
	    NO_OUTPUT=1
	    shift
	    ;;
	--nginx-dir)
	    NGINX_DIR="${2}"
	    shift 2
	    ;;
	--nginx-user)
	    NGINX_USER="${2}"
	    shift 2
	    ;;
	--nginx-group)
	    NGINX_GROUP="${2}"
	    shift 2
	    ;;
	--traefik-dir)
	    TRAEFIK_DIR="${2}"
	    shift 2
	    ;;
	--traefik-user)
	    TRAEFIK_USER="${2}"
	    shift 2
	    ;;
	--traefik-group)
	    TRAEFIK_GROUP="$2"
	    shift 2
	    ;;
	--)
	    shift
	    break
	    ;;
	*)
	    echo "Unsupported option: ${1}"
	    exit 3
	    ;;
    esac
done

export ENV_FILE

if [ ! -f "${ENV_FILE}" ]; then
  echo -e "Missing .env file, please use the provided example and modify it according to your needs or specify one using the -e flag."
  exit 1
fi
source ./.env

if [ -z "${1}" ]; then
    quiet_print "Missing <dir> argument."
    exit 1
fi

# shellcheck disable=SC2086
CERT_DIR="$(realpath ${1})"
# shellcheck disable=SC2086
CERT_FILE="$(find ${CERT_DIR} -iname \*${MATCH_DOMAIN}\*.crt 2> /dev/null)"
# shellcheck disable=SC2086
KEY_FILE="$(find ${CERT_DIR} -iname \*${MATCH_DOMAIN}\*.key 2> /dev/null)"

# shellcheck disable=SC2086
if [[ "$(echo \"${CERT_FILE}\" | wc -w)" -gt 1 ]]; then
    quiet_print "More than 1 certificate files were found, please use --domain to narrow down to only one domain."
    exit 2
elif [[ "$(echo \"${KEY_FILE}\" | wc -w)" -gt 1 ]]; then
    quiet_print "More than 1 private key files were found, please use --domain to narrow down to only one domain."
    exit 2
fi

if [ -z "${CERT_FILE}" ]; then
    quiet_print "Could not find a file matching *${MATCH_DOMAIN}*.crt in the directory '${CERT_DIR}'."
    exit 2
fi

if [ -z "${KEY_FILE}" ]; then
    quiet_print "Could not find a file matching *${MATCH_DOMAIN}*.key in the directory '${CERT_DIR}'."
    exit 2
fi

if [ -z "${DST_CERT_NAME}" ]; then
    # shellcheck disable=SC2086
    DEST_CERT_FILENAME="$(basename ${CERT_FILE})"
else
    DEST_CERT_FILENAME="${DST_CERT_NAME}"
fi

if [ -z "${DST_KEY_NAME}" ]; then
    # shellcheck disable=SC2086
    DEST_KEY_FILENAME="$(basename ${KEY_FILE})"
else
    DEST_KEY_FILENAME="${DST_KEY_NAME}"
fi


###################
# Service updates #
###################
update_nginx
update_traefik

# Cleanup
cleanup
