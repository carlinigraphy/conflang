#!/usr/bin/env bats
# vim:ft=sh

function setup { load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'
   source "${BATS_TEST_DIRNAME}"/../lib/errors.sh
}


@test "exit statuses should be unique" {
   local -- expected="${#EXIT_STATUS[@]}"
   local -A codes=()

   for c in "${EXIT_STATUS[@]}" ; do
      codes[$c]=''
   done

   assert_equal "$expected" "${#codes[@]}"
}
