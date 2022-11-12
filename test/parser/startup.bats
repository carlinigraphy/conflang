#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   export lib_parser="${LIBDIR}/parser.sh"
   export lib_lexer="${LIBDIR}/lexer.sh"

   source "${LIBDIR}/errors.sh"
}


@test "successful source, ./lib/parser.sh" {
   source "$lib_parser"
}


@test "fails with no tokens" {
   source "$lib_parser"

   local -a TOKENS=()
   run parse

   assert_failure
   assert_output "Parse Error: didn't receive tokens from lexer."
   assert_equal  $status  "${EXIT_STATUS[parse_error]}"
}


@test "runs with only EOF token" {
   : 'While the parser should fail given *NO* tokens in the input, it should
      successfully parse an empty file (only EOF token).'

   source "$lib_parser"

   local -A TOKEN_0=( [type]='EOF' [value]='' )
   local -a TOKENS=( 'TOKEN_0' )

   run parse
   assert_success
}


@test "lexer -> parser with empty file" {
   : 'More complete test, starting from the lexer, transitioning into the
      parser. Testing handoff.'

   source "$lib_lexer"
   source "$lib_parser"

   local -a FILES=( /dev/stdin )
   lexer:init

   lexer:scan <<< ''
   parse
}


@test "lexer -> parser with simple data" {
   : 'Must check the lexer successfully hands off everything to the parser.
      and no additional global vars/functions are unspecified'

   source "$lib_lexer"
   source "$lib_parser"

   local -a FILES=( /dev/stdin )
   lexer:init

   lexer:scan <<< 'this (str): "that";'

   run parse
   assert_success
}
