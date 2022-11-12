#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/errors.sh"
}


@test "throw invalid fstring" {
   declare -a FILES=( /dev/stdin )

   lexer:init
   run lexer:scan <<< 'f"{^str}"'

   assert_output "Syntax Error: \`^' not valid in string interpolation."
   assert_equal  $status  "${EXIT_STATUS[invalid_interpolation_char]}"
}


@test "throw invalid fpath" {
   declare -a FILES=( /dev/stdin )

   lexer:init
   run lexer:scan <<< "f'{^str}'"

   assert_output "Syntax Error: \`^' not valid in string interpolation."
   assert_equal  $status  "${EXIT_STATUS[invalid_interpolation_char]}"
}


@test "throw unescaped brace, fstring" {
   declare -a FILES=( /dev/stdin )

   lexer:init
   run lexer:scan <<< 'f"}"'

   assert_output "Syntax Error: single \`}' not allowed in f-string."
   assert_equal  $status  "${EXIT_STATUS[unescaped_interpolation_brace]}"
}


@test "throw unescaped brace, fpath" {
   declare -a FILES=( /dev/stdin )

   lexer:init
   run lexer:scan <<< "f'}'"

   assert_output "Syntax Error: single \`}' not allowed in f-string."
   assert_equal  $status  "${EXIT_STATUS[unescaped_interpolation_brace]}"
}
