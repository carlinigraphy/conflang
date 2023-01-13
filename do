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


declare -a FILES=(
   "${PROGDIR}"/src/main
   "${PROGDIR}"/src/{lexer,parser,symbols,fold,files}.sh
   "${PROGDIR}"/src/{semantics,compiler,errors}.sh
)


case "$1" in
   'run')   shift ; "${PROGDIR}"/src/main  "$@"
            ;;

   'rundb') shift ; CONFC_TRACEBACK='sure'  "${PROGDIR}"/src/main  "$@"
            ;;

   'edit')  exec nvim -O3 "${FILES[@]}"
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
                  "${PROGDIR}"/src/main
                  "${PROGDIR}"/src/*.sh
               )
            fi
            shellcheck "${args[@]}" | less -R
            ;;


   'wc')    files=(
               "${PROGDIR}"/bin/*
               "${PROGDIR}"/src/*
            )
            wc -l "${files[@]}"
            ;;


   'wc-tests')
            params=(
               "${PROGDIR}"/test/
               -type  f
               -regex '.*.\(bats\|conf\)$'
            )
            wc -l $(find "${params[@]}")
            ;;

   'doc')   AWKDOC_LOG_LEVEL=1 awkdoc "${FILES[@]}"
            ;;

   'html')  AWKDOC_LOG_LEVEL=1 awkdoc "${FILES[@]}" > "${PROGDIR}/doc/out.md"
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
