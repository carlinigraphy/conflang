#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local SRC="${BATS_TEST_DIRNAME}/../src"
   source "${SRC}/errors.sh"
}


@test "exit statuses should be unique" {
   local -i expected="${#ERROR_CODE[@]}"
   local -A codes=()

   for c in "${ERROR_CODE[@]}" ; do
      codes[$c]=''
   done

   assert_equal "$expected"  "${#codes[@]}"
}


@test "only raises error types that exist" {
   while read -r ename ; do
      assert [ ${ERROR_CODE[$ename]} ]
   done < <(grep --no-filename -Po '(?<=raise )[[:alpha:]_]+' "${SRC}"/*)
}
