#!/usr/bin/env bash

PROGDIR=$( cd $(dirname "${BASH_SOURCE[0]}") ; pwd )
LIBDIR="${PROGDIR}"/../lib/


function usage {
cat <<EOF
usage ./$(basename "${BASH_SOURCE[0]}") <option>

options.
   -W | --strip-whitespace    Removes empty lines
   -C | --strip-comments      Removes comments
EOF

exit $1
}


invalid_opts=()
awk_opts=()

while (( $# )) ; do
   case "$1" in
      -W | --strip-whitespace)
         shift
         awk_opts+=( -v STRIP_WHITESPACE=yes )
         ;;

      -C | --strip-comments)
         shift
         awk_opts+=( -v STRIP_COMMENTS=yes )
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


if (( ${#invalid_opts[@]} )) ; then
   printf 'invalid opts:'
   printf ' [%s]'  "${invalid_opts[@]}"
   printf '\n'
   usage 1
fi


awk "${awk_opts[@]}" -f "${PROGDIR}"/fmt.awk "${LIBDIR}"/*.sh
