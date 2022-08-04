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

   'check') shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=(
                  "${PROGDIR}"/conflang
                  "${PROGDIR}"/lib/*.sh
               )
            fi
            exec shellcheck -x "${args[@]}"
            ;;

   'run')   shift
            exec "${PROGDIR}"/conflang "$@"
            ;;

   *) usage 1 ;;
esac
