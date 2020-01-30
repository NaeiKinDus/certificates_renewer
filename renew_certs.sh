#!/usr/bin/env bash

set -o errexit -o pipefail -o noclobber

function usage() {
    cat <<EOF
USAGE
\$> $0 run domain [ domain ... ]
\$> $0 renew domain [ ... domain ]

OPTIONS
-h/--help: show this menu
-v/--verbose: show more debug messages
-q/--quiet: no output, any error will be fatal
-s/--server <server_url>: URL to use to connect to ACME server
-l/--lego-bin <path_to_bin>: complete path to the lego binary
-d/--dot-lego-dir <path_to_dir>: path to the .lego directory (generated when using the \`run\` command)
-t/--dry-run: use the staging ACME server"
-o/--ocscp-stapling: force OCSP stapling (--must-staple option for lego)
EOF
}

#####################
# Utility functions #
#####################
# https://stackoverflow.com/a/45201229
function mfcb {
    local val="$4";
    "$1";
    eval "$2[$3]=\$val;";
}

function val_ltrim {
    if [[ "$val" =~ ^[[:space:]]+ ]]; then
	val="${val:${#BASH_REMATCH[0]}}";
    fi;
}

function val_rtrim {
    if [[ "$val" =~ [[:space:]]+$ ]]; then
	val="${val:0:${#val}-${#BASH_REMATCH[0]}}";
    fi;
}

function val_trim {
    val_ltrim;
    val_rtrim;
}

function quiet_print() {
    if [[ $NO_OUTPUT -eq 0 ]]; then
	echo -e $1
    fi
}

function verbose_print() {
    if [[ $VERBOSE -eq 1 ]]; then
	quiet_print "$1"
    fi
}

#####################
# Shellscript entry #
#####################
# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo -e "Getopt not available, please install linux-utils or similar package."
    exit 1
fi

## Options
OPTIONS=s:vl:d:htqoe:
LONGOPTS=server:,verbose,lego-bin:,dot-lego:,help,dry-run,quiet,ocsp-stapling,email:

! PARSED=$(getopt --options=${OPTIONS} --longoptions=${LONGOPTS} --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    exit 2
fi

eval set -- "${PARSED}"
ACME_SERVER="https://acme-v02.api.letsencrypt.org/directory"
VERBOSE=0
LEGO_BIN=
DOT_LEGO_DIR=
NO_OUTPUT=0
STAPLE=""
EMAIL=""

while true; do
    case "$1" in
	-h|--help)
	    usage
	    exit 0
	    ;;
	-e|--email)
	    EMAIL="$2"
	    shift 2
	    ;;
	-q|--quiet)
	    NO_OUTPUT=1
	    shift
	    ;;
	-s|--server)
	    ACME_SERVER="$2"
	    shift 2
	    ;;
	-v|--verbose)
	    VERBOSE=1
	    shift
	    ;;
	-l|--lego-bin)
	    LEGO_BIN="$2"
	    shift 2
	    ;;
	-o|--ocsp-stapling)
	    STAPLE="--must-staple"
	    shift
	    ;;
	-d|--dot-lego)
	    DOT_LEGO_DIR="$2"
	    shift 2
	    ;;
	-t|--dry-run)
	    ACME_SERVER="https://acme-staging-v02.api.letsencrypt.org/directory"
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

SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

if [ -z "${DOT_LEGO_DIR}" ]; then
    DOT_LEGO_DIR="$(dirname ${SCRIPT_PATH})/.lego"
    if [ ! -d "${DOT_LEGO_DIR}" ]; then
	mkdir -p ${DOT_LEGO_DIR}
    fi
fi

if [ "$1" == "hook" ]; then
    quiet_print "Running hook..."
    DOMAIN=$2

    if [ -z "${DOMAIN}" ]; then
	quiet_print "Missing domain name, invalid hook call"
	exit 1
    fi

    SERVICES_DAT_FILE="$(dirname ${0})/services.dat"
    if [ ! -f $SERVICES_DAT_FILE ]; then
	quiet_print "File ${SERVICES_DAT_FILE} does not exist."
	exit 1
    fi

    # If it is a wildcard domain, replace the leading * with _
    if [[ $DOMAIN = \** ]]; then
	DOMAIN_FILE=${DOMAIN/\*/_}
	DOMAIN=${DOMAIN/\*\./}
	IS_WILDCARD=1
    else
	IS_WILDCARD=0
    fi

    verbose_print "Checking for ${DOMAIN} files"

    # Looks for a local ssh_key file for scp actions
    if [ -z $SSH_ID ]; then
	SSH_ID="$(dirname $0)/ssh_key"
    fi

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

	readarray -c1 -C 'mfcb val_trim DOMAIN_DATA' -td, <<<"${LINE}";
	DNAME=${DOMAIN_DATA[0]}
	METHOD=${DOMAIN_DATA[1]}
	METHOD_ARGS=${DOMAIN_DATA[2]}

	if [ "${DOMAIN}" != "${DNAME}" ]; then
	    verbose_print "- ignoring service line for domain ${DNAME}"
	    continue
	fi

	if [ ! ${VALID_METHODS["$METHOD"]} ]; then
	    quiet_print "${METHOD} is not a valid method, skipping."
	    continue
	fi

	if [[ $METHOD == "ssh" || $METHOD == "scp" ]]; then
	    if [ ! -f $SSH_ID ]; then
		quiet_print "Could not find SSH identity file, skipping."
		continue
	    fi
	    METHOD_ARGS="-i ${SSH_ID} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${METHOD_ARGS}"
	fi

	METHOD_ARGS="$(echo $METHOD_ARGS | envsubst)"
	verbose_print "- exec: ${METHOD} ${METHOD_ARGS} 2> /dev/null"
	$(${METHOD} ${METHOD_ARGS} 2> /dev/null)
    done < $SERVICES_DAT_FILE
    exit 0
fi

declare -A ACTIONS=([run]=1 [renew]=1)
if [ ! ${ACTIONS["$1"]} ]; then
    quiet_print "$1 is not a valid action to perform on a certificate, supports 'run' and 'renew'"
    exit 1
else
    ACTION=$1
    shift
fi

if [ -z "${EMAIL}" ]; then
    quiet_print "You must provide an email address"
    exit 1
fi

if [ -z $API_KEY ]; then
    quiet_print "Missing API_KEY environment variable, aborted."
    exit 1
fi

if [ -z $TIMEOUT ]; then
    GANDIV5_PROPAGATION_TIMEOUT=400
else
    GANDIV5_PROPAGATION_TIMEOUT=$TIMEOUT
fi

if [ -z "${LEGO_BIN}" ]; then
    LEGO_BIN="$(/usr/bin/which lego 2> /dev/null)"
fi

if [ ! -f "${LEGO_BIN}" ]; then
    quiet_print "Could not locate 'lego' binary, please ensure it is installed and reachable, or specify the environment variable LEGO_BIN"
    exit 1
fi

if [ "$#" -lt 1 ]; then
    quiet_print "Missing at least one domain, aborted."
    exit 1
fi

for DOMAIN in $*
do
    quiet_print "Processing domain ${DOMAIN}..."
    if [[ $ACTION == "run" ]]; then
	verbose_print "Starting command \"run\" with lego..."
	verbose_print "GANDIV5_API_KEY=${API_KEY} ${LEGO_BIN} --server ${ACME_SERVER} --path ${DOT_LEGO_DIR} --domains ${DOMAIN} --accept-tos --email ${EMAIL} --dns gandiv5 run ${STAPLE} > /dev/null"
	GANDIV5_API_KEY=${API_KEY} ${LEGO_BIN} --server ${ACME_SERVER} --path ${DOT_LEGO_DIR} --domains ${DOMAIN} --accept-tos --email ${EMAIL} --dns gandiv5 run ${STAPLE} > /dev/null
	if [ $? -eq 0 ]; then
	    verbose_print "Successful \"run\", calling the script in hook mode..."
	    ${SCRIPT_PATH} hook ${DOMAIN}
	else
	    quiet_print "Could not generate a new certificate, hook will not be executed !"
	    continue
	fi
    elif [[ $ACTION == "renew" ]]; then
	verbose_print "Starting command \"renew\" with lego..."
	verbose_print "GANDIV5_API_KEY=${API_KEY} ${LEGO_BIN} --server ${ACME_SERVER} --path ${DOT_LEGO_DIR} --domains ${DOMAIN} --accept-tos --email ${EMAIL} --dns gandiv5 renew --renew-hook "$0 hook ${DOMAIN}" --days 90 ${STAPLE} > /dev/null"
	GANDIV5_API_KEY=${API_KEY} ${LEGO_BIN} --server ${ACME_SERVER} --path ${DOT_LEGO_DIR} --domains ${DOMAIN} --accept-tos --email ${EMAIL} --dns gandiv5 renew --renew-hook "$0 hook ${DOMAIN}" --days 90 ${STAPLE} > /dev/null
	if [ $? -eq 0 ]; then
	    quiet_print "Certificate renewed successfully renewed for ${DOMAIN}"
	else
	    quiet_print "Certificate could not be renewed for domain ${DOMAIN}"
	fi
    fi
done
