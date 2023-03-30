#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local SRC="${BATS_TEST_DIRNAME}/../../src"
   source "${SRC}/main"
   source "${SRC}/locations.sh"
   source "${SRC}/lexer.sh"
   source "${SRC}/errors.sh"

   globals:init
   file:new
   file:resolve "/dev/stdin"
}


@test "throw invalid fstring" {
   lexer:init
   run lexer:scan <<< 'f"{^str}"'

   assert_output --partial "invalid character in fstring [^]"
   assert_equal  $status   "${ERROR_CODE[invalid_interpolation_char]%%,*}"
}


@test "throw invalid fpath" {
   lexer:init
   run lexer:scan <<< "f'{^str}'"

   assert_output --partial "invalid character in fstring [^]"
   assert_equal  $status   "${ERROR_CODE[invalid_interpolation_char]%%,*}"
}


@test "throw unescaped brace, fstring" {
   lexer:init
   run lexer:scan <<< 'f"}"'

   assert_output --partial "single \`}' not allowed in f-string."
   assert_equal  $status   "${ERROR_CODE[unescaped_interpolation_brace]%%,*}"
}


@test "throw unescaped brace, fpath" {
   lexer:init
   run lexer:scan <<< "f'}'"

   assert_output --partial "single \`}' not allowed in f-string."
   assert_equal  $status   "${ERROR_CODE[unescaped_interpolation_brace]%%,*}"
}
