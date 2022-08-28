#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../lib"
   export lib_lexer="${LIBDIR}/lexer.sh"
   export lib_parser="${LIBDIR}/parser.sh"
}


@test "lexer does not include \`p_\` prefixed functions" {
   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   # Source in the lexer, compile list of function names. None of these should
   # begin with an `p_` prefix.
   source "$lib_lexer"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=()
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
          [[ ! "$f" =~ ^p_ ]]
      fi
   done
}


@test "parser does not include \`l_\` prefixed functions" {
   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   # Source in the parser, compile list of function names. None of these should
   # begin with an `l_` prefix.
   source "$lib_parser"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=()
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
          [[ ! "$f" =~ ^l_ ]]
      fi
   done
}
