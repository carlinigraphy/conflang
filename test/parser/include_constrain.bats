#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   export conflang="${LIBDIR}/../conflang"

   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/errors.sh"
}


@test "successful source, ./conflang" {
   source "$conflang"
}


@test "include in absolute directory" {
   local parent_d="$( mktemp -p "$BATS_RUN_TMPDIR" -d  'parent_d.XXX' )"
   local parent_f="$( mktemp -p "$parent_d"            'parent_f.XXX' )"
   trap 'rm "$parent_f" ; rmdir "$parent_d"' EXIT

   local child_d="$( mktemp -p "$parent_d" -d  'child_d.XXX' )"
   local child_f="$( mktemp -p "$child_d"      'child_f.XXX' )"
   trap 'rm "$child_f"  ; rmdir "$child_d"'  EXIT
}
