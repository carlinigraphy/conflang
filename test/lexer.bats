#!/usr/bin/env bats
# vim:ft=bash

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export lexer=$( realpath "${BATS_TEST_DIRNAME}"/../lib/lexer.sh )
   export files="${BATS_TEST_DIRNAME}"/lexer_files
}

@test "lexer fails with no input" { skip; }
@test "lexer runs with empty file" { skip; }

@test "lexer correctly identifies integers" { skip; }
@test "lexer correctly identifies keywords" {
   run $lexer
   echo "$output" 1>&3
}
