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
--cron-mode: existence checks of certificates do not trigger an error and silently stop the command; useful when used with the cleanup action in a cron setting
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
LONGOPTS=help,verbose,email:,env:,dry-run,domain:,cert-name:,key-name:,quiet,cron-mode

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
CRON_MODE=${CRON_MODE:=0}

export DRY_RUN
export EMAIL_CONTACT
export NO_OUTPUT
export VERBOSE
export CRON_MODE

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
	--cron-mode)
	    CRON_MODE=1
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

ACTIONS_CFG_FILE="${SCRIPT_DIR}""/actions.cfg"
if [ ! -f "${ACTIONS_CFG_FILE}" ]; then
  quiet_print "File ${ACTIONS_CFG_FILE} does not exist."
  exit 1
fi

CERT_DIR="$(realpath "${1}")"
CERT_FILE="$(find "${CERT_DIR}" -iname \*"${MATCH_DOMAIN}"\*.crt 2> /dev/null || true)"
KEY_FILE="$(find "${CERT_DIR}" -iname \*"${MATCH_DOMAIN}"\*.key 2> /dev/null || true)"

# shellcheck disable=SC2086
if [[ "$(echo \"${CERT_FILE}\" | wc -w)" -gt 1 ]]; then
    quiet_print "More than 1 certificate files were found, please use --domain to narrow down to only one domain."
    exit 2
elif [[ "$(echo \"${KEY_FILE}\" | wc -w)" -gt 1 ]]; then
    quiet_print "More than 1 private key files were found, please use --domain to narrow down to only one domain."
    exit 2
fi

if [ -z "${CERT_FILE}" ]; then
    if [[ ${CRON_MODE} -eq 1 ]]; then
      verbose_print "Could not find a file matching *${MATCH_DOMAIN}*.crt in the directory '${CERT_DIR}'."
      exit 0
    fi
    quiet_print "Could not find a file matching *${MATCH_DOMAIN}*.crt in the directory '${CERT_DIR}'."
    exit 2
fi
export CERT_FILE

if [ -z "${KEY_FILE}" ]; then
    quiet_print "Could not find a file matching *${MATCH_DOMAIN}*.key in the directory '${CERT_DIR}'."
    exit 2
fi
export KEY_FILE

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
# Loading enabled actions #
#############################
shopt -s nullglob
module_executed=0
perform_cleanup=0
quiet_print "loading enabled actions..."
for action in "${SCRIPT_DIR}"/enabled-actions/*.sh; do
  if [[ "${action}" =~ .*/cleanup.sh ]]; then
    verbose_print "- cleanup required, will be executed after all the other actions are executed"
    perform_cleanup=1
  else
    verbose_print "- loading ""${action}"
    source "${action}"
  fi
done

################################
# Executing configured actions #
################################
while read -r LINE; do
  if [[ ${LINE:0:1} == "#" ]]; then
    continue
  fi

  # shellcheck disable=SC2086
  LINE="$(echo $LINE | envsubst)"

  readarray -c1 -C 'mfcb val_trim CALL_STACK' -td, <<<"${LINE}"
  verbose_print "Executing '${CALL_STACK[*]}'"
  if [ -n "$(LC_ALL=C type -t "${CALL_STACK[0]}")" ]; then
      module_executed=1
      ${CALL_STACK[*]}
  else
    quiet_print "Action '${CALL_STACK[0]}' does not exist, ignored"
  fi
  unset CALL_STACK
done <"${ACTIONS_CFG_FILE}"

if [ $perform_cleanup -eq 1 ]; then
  quiet_print "performing cleanup..."
  if [[ ${DRY_RUN} -eq 1 ]]; then
    quiet_print "executing ${SCRIPT_DIR}/enabled-actions/cleanup.sh"
  fi
  source "${SCRIPT_DIR}"/enabled-actions/cleanup.sh
  cleanup
fi

if [ $module_executed -eq 0 ]; then
  quiet_print "WARNING: no action were called, this script performed absolutely nothing."
fi

quiet_print "done."
exit 0
