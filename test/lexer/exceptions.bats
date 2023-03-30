#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local src="${BATS_TEST_DIRNAME}/../../src"
   source "${src}/main"
   source "${src}/locations.sh"
   source "${src}/lexer.sh"
   source "${src}/errors.sh"

   export F=$( mktemp "${BATS_TEST_TMPDIR}"/XXX ) 
   globals:init

   file:new
   file:resolve "/dev/stdin"
}


@test "raise syntax_error on ERROR token" {
   lexer:init
   run lexer:scan <<< '&'

   assert_failure
   assert_output --partial 'Syntax Error('
   assert_output --partial 'invalid character [&]'
}


@test "raise error on unterminated string" {
   lexer:init
   run lexer:scan <<< '"'

   assert_failure
}


@test "raise error on unterminated path" {
   lexer:init
   run lexer:scan <<< "'"

   assert_failure
}
