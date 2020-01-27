#!/usr/bin/env bash

# https://stackoverflow.com/a/45201229
function mfcb {
    local val="$4";
    "$1";
    eval "$2[$3]=\$val;";
};

function val_ltrim {
    if [[ "$val" =~ ^[[:space:]]+ ]]; then
	val="${val:${#BASH_REMATCH[0]}}";
    fi;
};

function val_rtrim {
    if [[ "$val" =~ [[:space:]]+$ ]]; then
	val="${val:0:${#val}-${#BASH_REMATCH[0]}}";
    fi;
};

function val_trim {
    val_ltrim;
    val_rtrim;
};

if [ -z "${DOT_LEGO_DIR}" ]; then
    DOT_LEGO_DIR="$(dirname $0)/.lego"
    if [ ! -d "${DOT_LEGO_DIR}" ]; then
	"$(mkdir -p ${DOT_LEGO_DIR})"
    fi
fi

if [ "$1" == "hook" ]; then
    echo -e "Running hook..."
    DOMAIN=$2

    if [ -z "${DOMAIN}" ]; then
	echo -e "Missing domain name, invalid hook call"
	exit 1
    fi

    if [ -z $SSH_ID ]; then
	SSH_ID="$(dirname $0)/ssh_key"
    fi

    export CERT_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN}.crt"
    export PRIV_KEY_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN}.key"
    export ISSUER_PATH="${DOT_LEGO_DIR}/certificates/${DOMAIN}.issuer.crt"
    export CERT_DIR_PATH="${DOT_LEGO_DIR}/certificates"

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
	    continue
	fi

	if [ ! ${VALID_METHODS["$METHOD"]} ]; then
	    >&2 echo -e "${METHOD} is not a valid method, skipping."
	    continue
	fi

	if [[ $METHOD == "ssh" || $METHOD == "scp" ]]; then
	    if [ ! -f $SSH_ID ]; then
		>&2 echo -e "Could not find SSH identity file, skipping."
		continue
	    fi
	    METHOD_ARGS="-i ${SSH_ID} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${METHOD_ARGS}"
	fi

	METHOD_ARGS="$(echo $METHOD_ARGS | envsubst)"
	echo -e "Executing: ${METHOD} ${METHOD_ARGS}"
	#$(${METHOD} ${METHOD_ARGS} 2> /dev/null)
    done < "$(dirname ${0})/services.dat"
    
    exit 0
fi

declare -A ACTIONS=([run]=1 [renew]=1)
if [ ! ${ACTIONS["$1"]} ]; then
    >&2 echo -e "$1 is not a valid action to perform on a certificate, supports 'new' and 'renew'"
    exit 1
else
    ACTION=$1
    shift
fi

if [ -z $API_KEY ]; then
    echo -e "Missing API_KEY environment variable, aborted."
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
    >&2 echo -e "Could not locate 'lego' binary, please ensure it is installed and reachable, or specify the environment variable LEGO_BIN"
    exit 1
fi

if [ "$#" -lt 1 ]; then
    echo -e "Missing at least one domain, aborted."
    exit 1
fi

for DOMAIN in $*
do
    echo -e "Renewing for domain ${DOMAIN}..."
    if [[ $ACTION == "run" ]]; then
	"$(GANDIV5_API_KEY=${API_KEY} ${LEGO_BIN} --server https://acme-staging-v02.api.letsencrypt.org/directory --path ${DOT_LEGO_DIR} --domains ${DOMAIN} --accept-tos --email naeikindus@0x2a.ninja --dns gandiv5 run --must-staple)"
	#if [ $? -eq 0 ]; then
	echo -e "\tRunning hook for newly created certificates..."
	"$($0 hook ${DOMAIN})"
	### Gets an error, file not found, no idea why
	#else
	#    >&2 echo -e "\tCould not generate a new certificate, hook will not be executed !"
	#    continue
	#fi
    elif [[ $ACTION == "renew" ]]; then
	"$(GANDIV5_API_KEY=${API_KEY} ${LEGO_BIN} --server https://acme-staging-v02.api.letsencrypt.org/directory --path ${DOT_LEGO_DIR} --domains ${DOMAIN} --accept-tos --email naeikindus@0x2a.ninja --dns gandiv5 renew --must-staple --renew-hook \"$0 hook ${DOMAIN}\" --days 90)"
    fi
done
