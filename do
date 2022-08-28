#!/bin/bash

declare -g PROGDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" ; pwd )


function usage {
cat <<EOF

./do COMMAND

commands
   test        Run \`BATS\` tests
   cov         Run \`BATS\` tests with \`kcov\` coverage
   res         View result of \`kcov\` in browser
   check       Run \`shellcheck\`
   wc          Lines of bash
   wc-tests    Lines of BATS
   edit        Opens src files in \$EDITOR

EOF

exit "$1"
}


case "$1" in
   'test')  shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=( "${PROGDIR}"/test )
            fi
            exec bats -r "${args[@]}"
            ;;


   'cov')   shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=( "${PROGDIR}"/test )
            fi
            kargs=(
               --bash-dont-parse-binary-dir
               --include-path="${PROGDIR}"
               "${PROGDIR}"/.coverage
               bats -r --pretty
            )
            kcov "${kargs[@]}" "${args[@]}" 2>/dev/null
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


   'wc')    files=(
               "${PROGDIR}"/conflang
               "${PROGDIR}"/lib/*
            )
            exec wc -l "${files[@]}"
            ;;


   'wc-tests')
            params=(
               "${PROGDIR}"/test/
               -type  f
               -regex '.*.\(bats\|conf\)'
            )
            exec wc -l $(find "${params[@]}")
            ;;


   'edit')  order=(
               "${PROGDIR}"/conflang
               "${PROGDIR}"/lib/{lexer,parser,compiler}.sh
               "${PROGDIR}"/lib/{errors,debug}.sh
            )
            exec nvim "${order[@]}"
            ;;

   *) usage 1 ;;
esac
