#!/usr/bin/bats
# vim:ft=sh
#
# Specifically for testing the functionality of the Pratt parser. We're
# covering all the regular NUD operations in ./ast.bats, really only need to
# test more advanced maneuvers. Multiple concatenations in a single string,
# operator precedence for typecasts that have a complex left expression, etc.

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local src="${BATS_TEST_DIRNAME}/../../src"
   source "${src}/main"
   source "${src}/locations.sh"
   source "${src}/lexer.sh"
   source "${src}/parser.sh"
   source "${src}/errors.sh"

   globals:init
   file:new
   file:resolve "/dev/stdin"
}

#@test "operator precedence, typecast" {
#   skip
#}
