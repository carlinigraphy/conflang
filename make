#!/bin/bash

declare -g PROGDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" ; pwd )


function usage {
cat <<EOF
./make (test | check | run <FILE>)
EOF
exit "$1"
}


case "$1" in
   'test')  shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=( "${PROGDIR}"/test )
            fi
            exec bats "${args[@]}"
            ;;


   'cov')   shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=( "${PROGDIR}"/test )
            fi
            kargs=(
               --bash-dont-parse-binary-dir
               --include-path="${PROGDIR}"
               "${PROGDIR}"/.coverage
               bats --pretty
            )
            exec kcov "${kargs[@]}" "${args[@]}" 2>/dev/null
            ;;


   'res')   shift
            exec xdg-open "${PROGDIR}"/.coverage/index.html
            ;;


   'check') shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=(
                  "${PROGDIR}"/conflang
                  "${PROGDIR}"/lib/*.sh
               )
            fi
            exec shellcheck -s bash -x "${args[@]}"
            ;;


   'run')   shift
            exec "${PROGDIR}"/conflang "$@"
            ;;

   *) usage 1 ;;
esac
