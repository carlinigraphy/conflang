#!/usr/bin/env bats
# vim:ft=sh

function setup { load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../lib"
   source "${LIBDIR}"/errors.sh
}


@test "exit statuses should be unique" {
   local -- expected="${#EXIT_STATUS[@]}"
   local -A codes=()

   for c in "${EXIT_STATUS[@]}" ; do
      codes[$c]=''
   done

   assert_equal "$expected" "${#codes[@]}"
}


@test "only raises error types that exist" {
   while read -r ename ; do
      assert [ ${EXIT_STATUS[$ename]} ]
   done < <(grep --no-filename -Po '(?<=raise )[[:alpha:]_]+' "${LIBDIR}"/*.sh)
}
