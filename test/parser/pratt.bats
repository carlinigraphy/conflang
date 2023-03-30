#!/usr/bin/bats
# vim:ft=sh

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
