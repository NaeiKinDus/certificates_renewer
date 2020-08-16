set -o errexit -o pipefail -o noclobber

#####################
# Utility functions #
#####################
# https://stackoverflow.com/a/45201229
function mfcb() {
  local val="$4"
  "$1"
  eval "$2[$3]=\$val;"
}

function val_ltrim() {
  if [[ "$val" =~ ^[[:space:]]+ ]]; then
    val="${val:${#BASH_REMATCH[0]}}"
  fi
}

function val_rtrim() {
  if [[ "$val" =~ [[:space:]]+$ ]]; then
    val="${val:0:${#val}-${#BASH_REMATCH[0]}}"
  fi
}

function val_trim() {
  val_ltrim
  val_rtrim
}

function quiet_print() {
  if [[ $NO_OUTPUT -eq 0 ]]; then
    echo -e "${1}"
  fi
}

function verbose_print() {
  if [[ $VERBOSE -eq 1 ]]; then
    quiet_print "${1}"
  fi
}

function copy_files() {
  SRC_FILE="${1}"
  DST_FILE="${2}"

  if [ -z "${SRC_FILE}" ]; then
    quiet_print "No source file given"
    exit 3
  elif [ -z "${DST_FILE}" ]; then
    quiet_print "No destination file given"
    exit 3
  fi

  verbose_print "Copying ${SRC_FILE} to ${DST_FILE}"
  if [[ $DRY_RUN -eq 1 ]]; then
    quiet_print "/bin/cp ${SRC_FILE} ${DST_FILE}"
  else
    verbose_print "/bin/cp ${SRC_FILE} ${DST_FILE}"
    /bin/cp "${SRC_FILE}" "${DST_FILE}"
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      quiet_print "Could not copy files to ${DST_FILE}"
      exit 4
    fi
  fi
}

function do_chown() {
  USER="${1}"
  shift
  GROUP="${1}"
  shift

  for ITEM in "${@}"; do
    if [ "${VERBOSE}" -eq 1 ] || [ "${DRY_RUN}" -eq 1 ]; then
      echo "chown ${USER}:${GROUP} ${ITEM}"
    fi
    if [ "$DRY_RUN" -ne 1 ]; then
      chown "${USER}:${GROUP}" "${ITEM}"
    fi
  done
}
