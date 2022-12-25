#!/usr/bin/env bash

PROGDIR=$( cd $(dirname "${BASH_SOURCE[0]}") ; pwd )
SRCDIR="${PROGDIR}"/../src/


function usage {
cat <<EOF
usage ./$(basename "${BASH_SOURCE[0]}") <option>

options.
   -w | --strip-newlines    Removes empty lines
   -c | --strip-comments    Removes comments
   -t | --topic <TOPIC>     Subscribes to TOPIC
EOF

exit $1
}

topics=''
invalid_opts=()
awk_opts=()

while (( $# )) ; do
   case "$1" in
      -h | --help)
         usage 0
         ;;

      -w | --strip-whitespace)
         shift
         awk_opts+=( -v STRIP_WHITESPACE=yes )
         ;;

      -c | --strip-comments)
         shift
         awk_opts+=( -v STRIP_COMMENTS=yes )
         ;;

      -t | --topic)
         shift
         topics+="${topics:=,}${1}"
         ;;

      -[^-]*)
         opt="${1/-/}"; newopts=()
         while [[ "$opt" =~ . ]] ; do
            char=${BASH_REMATCH[0]}
            newopts+=( -${char} )
            opt="${opt/${char}/}"
         done
         shift

         # If there's only 1 match that hasn't been handled by a valid option
         # above, it's an error. Add to invalid, and continue.
         if (( ${#newopts[@]} == 1 )) ; then
            invalid_opts+=( ${newopts[@]} )
            continue
         fi

         set -- "${newopts[@]}"  "$@"
         ;;

      *)
         invalid_opts+=( "$1" ) ; shift
         ;;
   esac
done

awk_opts+=(
   -v SUBSCRIBE="$topics"
)

if (( ${#invalid_opts[@]} )) ; then
   printf 'invalid opts:'
   printf ' [%s]'  "${invalid_opts[@]}"
   printf '\n'
   usage 1
fi

awk "${awk_opts[@]}"  -f "${PROGDIR}"/preproc.awk  "${SRCDIR}"/*.sh  "${SRCDIR}"/main
