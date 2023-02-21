#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local SRC="${BATS_TEST_DIRNAME}/../src"
   export _LEXER_SH="${SRC}/lexer.sh"
   export _PARSER_SH="${SRC}/parser.sh"
}


@test "lexer does not include \`parser\` prefixed functions" {
   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_:]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   # Source in the lexer, compile list of function names. None of these should
   # begin with an `parser:` prefix.
   source "$_LEXER_SH"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=()
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
          [[ ! "$f" =~ ^parser: ]]
      fi
   done
}


@test "parser does not include \`lexer:\` prefixed functions" {
   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_:]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   # Source in the parser, compile list of function names. None of these should
   # begin with an `lexer:` prefix.
   source "$_PARSER_SH"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=()
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
          [[ ! "$f" =~ ^lexer: ]]
      fi
   done
}
