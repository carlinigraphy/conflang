#!/bin/bash

declare -g PROGDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" ; pwd )


function usage {
cat <<EOF

./do COMMAND

commands
   run         Runs \`confc\`
   rundb       Runs \`confc\` with debug flag(s)
   test        Run \`BATS\` tests
   cov         Run \`BATS\` tests with \`kcov\` coverage
   check       Run \`shellcheck\`
   wc          Lines of bash
   wc-tests    Lines of BATS
   edit        Opens src files in vim

EOF

exit "$1"
}


case "$1" in
   'run')   shift ; exec "${PROGDIR}"/bin/confc "$@"
            ;;

   'rundb') shift ; CONFC_DEBUG='t' exec "${PROGDIR}"/bin/confc "$@"
            ;;

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
                  "${PROGDIR}"/bin/confc
                  "${PROGDIR}"/lib/*.sh
               )
            fi
            exec shellcheck -s bash -x "${args[@]}"
            ;;


   'wc')    files=(
               "${PROGDIR}"/bin/*
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
               "${PROGDIR}"/bin/confc
               "${PROGDIR}"/lib/utils.sh
               "${PROGDIR}"/lib/{lexer,parser,semantics,compiler}.sh
               "${PROGDIR}"/lib/{errors,debug,ffi}.sh
            )
            exec nvim -O3 "${order[@]}"
            ;;

   *) usage 1 ;;
esac
