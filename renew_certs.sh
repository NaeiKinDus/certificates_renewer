#!/usr/bin/env bash

set -o pipefail -o noclobber

function usage() {
  cat <<EOF
USAGE
\$> $0 run domain [ domain ... ]
\$> $0 renew domain [ domain ... ]

ARGUMENTS
domain [ domain ...]: list of domains the script will configure / renew

OPTIONS
-h/--help: show this menu
-v/--verbose: show more debug messages
-q/--quiet: no output, any error will be fatal
-e/--env: specify an environment file
-s/--server <server_url>: URL to use to connect to ACME server
-d/--dry-run: use the staging ACME server
-o/--ocscp-stapling: force OCSP stapling (--must-staple option for lego)
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/"
SCRIPT_PATH=${SCRIPT_DIR}$(basename "${BASH_SOURCE[0]}")

source "${SCRIPT_DIR}/common.sh"

#####################
# Shell script entry #
#####################
# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
! getopt --test >/dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
  echo -e "Getopt not available, please install linux-utils or similar package."
  exit 1
fi

## Options
OPTIONS=s:e:vhdqo
LONGOPTS=server:,env:,verbose,help,dry-run,quiet,ocsp-stapling

! PARSED=$(getopt --options=${OPTIONS} --longoptions=${LONGOPTS} --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
  exit 2
fi

if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

eval set -- "${PARSED}"
ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
VERBOSE=${VERBOSE:=0}
LEGO_BIN=${LEGO_BIN:=""}
DOT_LEGO_DIR=${DOT_LEGO_DIR:=""}
NO_OUTPUT=${NO_OUTPUT:=0}
STAPLE=${STAPLE:=""}
EMAIL_CONTACT=${EMAIL_CONTACT:=""}
DRY_RUN=${DRY_RUN:=0}
DNS_CHALLENGE_TYPE=${DNS_CHALLENGE_TYPE}
ENV_FILE=${ENV_FILE:=".env"}
DNS_RESOLVERS=${DNS_RESOLVERS:=""}

export DRY_RUN
export EMAIL_CONTACT
export NO_OUTPUT
export VERBOSE

while true; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  -q | --quiet)
    NO_OUTPUT=1
    shift
    ;;
  -s | --server)
    ACME_SERVER="$2"
    shift 2
    ;;
  -e | --env)
    ENV_FILE="$2"
    shift 2
    ;;
  -v | --verbose)
    VERBOSE=1
    shift
    ;;
  -o | --ocsp-stapling)
    STAPLE=1
    shift
    ;;
  -d | --dry-run)
    ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
    DRY_RUN=1
    shift
    ;;
  --)
    shift
    break
    ;;
  *)
    echo "Unsupported option: $1"
    exit 3
    ;;
  esac
done

export ENV_FILE

if [ ! -f "${ENV_FILE}" ]; then
  echo -e "Missing .env file, please use the provided example and modify it according to your needs or specify one using the -e flag."
  exit 1
fi
source "${SCRIPT_DIR}/.env"

if [ -z "${EMAIL_CONTACT}" ]; then
  quiet_print "You must provide an email address"
  exit 1
fi

if [ -z "${DOT_LEGO_DIR}" ]; then
  # shellcheck disable=SC2086
  DOT_LEGO_DIR="$(dirname ${SCRIPT_PATH})/.lego"
  if [ ! -d "${DOT_LEGO_DIR}" ]; then
    mkdir -p "${DOT_LEGO_DIR}"
  fi
fi

# Hook part, called either by lego during a renew or by this script itself during a run.
if [ "$1" == "hook" ]; then
  quiet_print "Running hook..."
  DOMAIN=$2

  if [ -z "${DOMAIN}" ]; then
    quiet_print "Missing domain name, invalid hook call"
    exit 1
  fi

  # shellcheck disable=SC2086
  SERVICES_DAT_FILE="$(dirname ${0})/services.dat"
  if [ ! -f "${SERVICES_DAT_FILE}" ]; then
    quiet_print "File ${SERVICES_DAT_FILE} does not exist."
    exit 1
  fi

  # If it is a wildcard domain, replace the leading * with _
  if [[ $DOMAIN == \** ]]; then
    DOMAIN_FILE=${DOMAIN/\*./}
    DOMAIN=${DOMAIN/\*\./}
    IS_WILDCARD=1
  else
    IS_WILDCARD=0
  fi

  verbose_print "Checking for ${DOMAIN} files"
  CURRENT_DIR=$(dirname "$0")
  export CURRENT_DIR
  if [[ $IS_WILDCARD -eq 1 ]]; then
    export CERT_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN_FILE}.crt"
    export PRIV_KEY_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN_FILE}.key"
    export ISSUER_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN_FILE}.issuer.crt"
  else
    export CERT_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN}.crt"
    export PRIV_KEY_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN}.key"
    export ISSUER_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN}.issuer.crt"
  fi
  export CERT_DIR_PATH="${DOT_LEGO_DIR}/certificates"

  verbose_print "CERT_PATH: ${CERT_PATH}"
  verbose_print "PRIV_KEY_PATH: ${PRIV_KEY_PATH}"
  verbose_print "ISSUER_PATH: ${ISSUER_PATH}"
  verbose_print "CERT_DIR_PATH: ${CERT_DIR_PATH}"

  declare -A VALID_METHODS=([scp]=1 [cp]=1 [ssh]=1)

  while read -r LINE; do
    if [[ ${LINE:0:1} == "#" ]]; then
      continue
    fi

    readarray -c1 -C 'mfcb val_trim DOMAIN_DATA' -td, <<<"${LINE}"
    DNAME=${DOMAIN_DATA[0]}
    METHOD=${DOMAIN_DATA[1]}
    METHOD_ARGS=${DOMAIN_DATA[2]}

    if [ "${DOMAIN}" != "${DNAME}" ]; then
      verbose_print "- ignoring service line for domain ${DNAME}"
      continue
    fi

    if [ ! "${VALID_METHODS["$METHOD"]}" ]; then
      quiet_print "${METHOD} is not a valid method, skipping."
      continue
    fi

    if [[ $METHOD == "ssh" || $METHOD == "scp" ]]; then
      METHOD_ARGS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${METHOD_ARGS}"
    fi

    # shellcheck disable=SC2086
    METHOD_ARGS="$(echo $METHOD_ARGS | envsubst)"
    verbose_print "- exec: ${METHOD} ${METHOD_ARGS} 2> /dev/null"

    if [[ ${DRY_RUN} -eq 1 ]]; then
      quiet_print "${METHOD} ${METHOD_ARGS} 2>/dev/null"
    else
      # shellcheck disable=SC2091
      # shellcheck disable=SC2086
      $(${METHOD} ${METHOD_ARGS} 2>/dev/null)
    fi
  done <"${SERVICES_DAT_FILE}"
  exit 0
fi

if [ -z "${DNS_CHALLENGE_TYPE}" ]; then
  quiet_print "No DNS challenge specified, refer to the file '.env.example' to know how to set it up."
  exit 1
fi

declare -A ACTIONS=([run]=1 [renew]=1)
if [ ! "${ACTIONS["$1"]}" ]; then
  quiet_print "$1 is not a valid action to perform on a certificate, supports 'run' and 'renew'"
  exit 1
else
  ACTION=$1
  shift
fi

if [ -z "${LEGO_BIN}" ]; then
  LEGO_BIN="$(command -v lego 2>/dev/null)"
fi

if [ ! -f "${LEGO_BIN}" ]; then
  quiet_print "Could not locate 'lego' binary (path: '${LEGO_BIN}'), please ensure it is installed and reachable, or specify the environment variable LEGO_BIN"
  exit 1
fi

# Find if provided DNS challenge is supported
mapfile -t -d ' ' MODULES_LIST < <("${LEGO_BIN}" dnshelp | awk '/All DNS codes/{modules=1;next}/More information/{modules=0}{gsub(/,/,"",$0)}modules{print}')
if [[ ! "${MODULES_LIST[*]}" =~ ${DNS_CHALLENGE_TYPE} ]]; then
  quiet_print "Invalid DNS challenge provided: ${DNS_CHALLENGE_TYPE}"
  quiet_print "Supported modules:\n${MODULES_LIST[*]}"
  exit 1
fi

if [ "$#" -lt 1 ]; then
  quiet_print "Missing at least one domain, aborted."
  exit 1
fi

for DOMAIN in "$@"; do
  quiet_print "Processing domain ${DOMAIN}..."
  BASE_ARGUMENTS=(--server "${ACME_SERVER}" --path "${DOT_LEGO_DIR}" --accept-tos --email "${EMAIL_CONTACT}" --dns "${DNS_CHALLENGE_TYPE}")

  if [ -n "${DNS_RESOLVERS}" ]; then
    BASE_ARGUMENTS+=(--dns.resolvers "${DNS_RESOLVERS}")
  fi

  # Handle wildcard domains
  if [[ $DOMAIN == \** ]]; then
    BASE_ARGUMENTS+=(--domains "${DOMAIN/\*./}")
  fi
  BASE_ARGUMENTS+=(--domains "${DOMAIN}")

  if [[ $ACTION == "run" ]]; then
    verbose_print "Starting command \"run\" with lego..."
    BASE_ARGUMENTS+=("run")
    if [[ $STAPLE -eq 1 ]]; then
      BASE_ARGUMENTS+=("--must-staple")
    fi

    if [[ $NO_OUTPUT -eq 1 ]]; then
      BASE_ARGUMENTS+=("> /dev/null")
    fi

    verbose_print "${LEGO_BIN} ${BASE_ARGUMENTS[*]}"

    if ${LEGO_BIN} "${BASE_ARGUMENTS[@]}"; then
      verbose_print "Successful \"run\", calling the script in hook mode..."
      ${SCRIPT_PATH} hook "${DOMAIN}"
    else
      quiet_print "Could not generate a new certificate, hook will not be executed !"
      continue
    fi
  elif [[ $ACTION == "renew" ]]; then
    verbose_print "Starting command \"renew\" with lego..."
    BASE_ARGUMENTS+=(renew --renew-hook "${0} hook ${DOMAIN}" --days 90)
    if [[ $STAPLE -eq 1 ]]; then
      BASE_ARGUMENTS+=("--must-staple")
    fi

    if [[ $NO_OUTPUT -eq 1 ]]; then
      BASE_ARGUMENTS+=("> /dev/null")
    fi

    verbose_print "${LEGO_BIN} ${BASE_ARGUMENTS[*]}"

    if ${LEGO_BIN} "${BASE_ARGUMENTS[@]}"; then
      quiet_print "Certificate renewed successfully renewed for ${DOMAIN}"
    else
      quiet_print "Certificate could not be renewed for domain ${DOMAIN}"
    fi
  fi
done
