#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   export lib_lexer="${LIBDIR}/lexer.sh"

   source "${LIBDIR}/errors.sh"
}


@test "successful source" {
   source "$lib_lexer"
}


@test "fails with no input" {
   source "$lib_lexer"
   run init_scanner

   assert_equal  "$status" "${EXIT_STATUS[no_input]}"
   assert_output 'File Error: missing input file.'
}


@test "runs with empty file" {
   : 'Given an empty input file, should successfully lex, generating only the
      final EOF token when closing the file.'

   declare -a FILES=( /dev/stdin )
   source "$lib_lexer"

   init_scanner
   scan <<< ''

   # Should have only an EOF token.
   assert [ ${#TOKENS[@]} -eq 1 ]

   local -n t="${TOKENS[0]}" 
   assert_equal "${t[type]}"  'EOF'
}
