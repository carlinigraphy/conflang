#!/bin/bash

declare -g PROGDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" ; pwd )


function usage {
cat <<EOF

./do COMMAND [FILE]

commands
   run         Runs \`confc\` on <FILE>
   rundb       Runs \`confc\` on <FILE> with debug flag(s) set
   test        Run \`BATS\` tests
   cov         Run \`BATS\` tests with \`kcov\` coverage
   check       Run \`shellcheck\`
   wc          Lines of bash
   wc-tests    Lines of BATS
   edit        Opens src files in nvim
   doc         Generates .md docs w/ \`awkdoc\`
   html        Generates .html docs w/ `awkdoc | pandoc`.

EOF

exit "$1"
}


case "$1" in
   'run')   shift ; "${PROGDIR}"/bin/confc "$@"
            ;;

   'rundb') shift ; CONFC_TRACEBACK='sure' "${PROGDIR}"/bin/confc "$@"
            ;;

   'edit')  order=(
               "${PROGDIR}"/bin/confc
               "${PROGDIR}"/lib/{lexer,parser,symbols,merge,files}.sh
               "${PROGDIR}"/lib/{semantics,compiler,errors}.sh
            )
            exec nvim -O3 "${order[@]}"
            ;;

   'test')  shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=( "${PROGDIR}"/test )
            fi
            bats -r "${args[@]}"
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
            xdg-open "${PROGDIR}"/.coverage/index.html
            ;;


   'check') shift ; args=( "$@" )
            if [[ ! "$args" ]] ; then
               args=(
                  --color=always
                  --shell=bash
                  --severity=warning
                  --external-sources 
                  "${PROGDIR}"/bin/confc
                  "${PROGDIR}"/lib/*.sh
               )
            fi
            shellcheck "${args[@]}" | less -R
            ;;


   'wc')    files=(
               "${PROGDIR}"/bin/*
               "${PROGDIR}"/lib/*
            )
            wc -l "${files[@]}"
            ;;


   'wc-tests')
            params=(
               "${PROGDIR}"/test/
               -type  f
               -regex '.*.\(bats\|conf\)'
            )
            wc -l $(find "${params[@]}")
            ;;

   'doc')   order=(
               "${PROGDIR}"/bin/confc
               "${PROGDIR}"/lib/{lexer,parser,symbols,merge,files}.sh
               "${PROGDIR}"/lib/{semantics,compiler,errors}.sh
            )
            AWKDOC_LOG_LEVEL=1 awkdoc "${order[@]}"
            ;;

   'html')  order=(
               "${PROGDIR}"/bin/confc
               "${PROGDIR}"/lib/{lexer,parser,symbols,merge}.sh
               "${PROGDIR}"/lib/{semantics,compiler}.sh
               "${PROGDIR}"/lib/{errors,debug,ffi}.sh
            )
            AWKDOC_LOG_LEVEL=1 awkdoc "${order[@]}" > "${PROGDIR}/doc/out.md"

            args=(
               --standalone
               --highlight-style monochrome
               --metadata title="documentation"
               -o "${PROGDIR}/doc/out.html"
            )
            pandoc "${args[@]}"  "${PROGDIR}/doc/out.md"
            ;;


   *) usage 1 ;;
esac
