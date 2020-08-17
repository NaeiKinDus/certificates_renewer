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
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034
SCRIPT_PATH=${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")

source "${SCRIPT_DIR}/common.sh"

#####################
# Shell script entry #
#####################
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo -e "Getopt not available, please install linux-utils or similar package."
    exit 1
fi

OPTIONS=hvm:e:ds:c:k:q
LONGOPTS=help,verbose,email:,env:,dry-run,domain:,cert-name:,key-name:,quiet

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
ENV_FILE=${ENV_FILE:="${SCRIPT_DIR}/.env"}

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
source "${ENV_FILE}"

if [ -z "${1}" ]; then
    quiet_print "Missing <dir> argument."
    exit 1
fi

CERT_DIR="$(realpath "${1}")"
CERT_FILE="$(find "${CERT_DIR}" -iname \*"${MATCH_DOMAIN}"\*.crt 2> /dev/null)"
KEY_FILE="$(find "${CERT_DIR}" -iname \*"${MATCH_DOMAIN}"\*.key 2> /dev/null)"

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
export DEST_CERT_FILENAME

if [ -z "${DST_KEY_NAME}" ]; then
    # shellcheck disable=SC2086
    DEST_KEY_FILENAME="$(basename ${KEY_FILE})"
else
    DEST_KEY_FILENAME="${DST_KEY_NAME}"
fi
export DEST_KEY_FILENAME

#############################
# Executing enabled actions #
#############################
shopt -s nullglob
module_executed=0
quiet_print "executing enabled actions..."
for action in "${SCRIPT_DIR}"/enabled-actions/*.sh; do
  module_executed=1
  verbose_print "- executing ""${action}"
  source "${action}"
done

if [ $module_executed -eq 0 ]; then
  quiet_print "WARNING: no action were called, this script performed absolutely nothing."
fi

quiet_print "done."
exit 0
