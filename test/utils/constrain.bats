#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"

   # These have functions that are directly invoked:
   source "${LIBDIR}/../conflang"      # init_globals()
   source "${LIBDIR}/utils.sh"         # add_file(), merge_includes()

   # These are more strictly library code. Nothing called directly.
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/errors.sh"

   # Create directory structure to test. Will look something like the following:
   #
   # $BATS_RUN_TMPDIR (/tmp/bats-run-XXXX)
   #  └── parent_d.cmj                          $PARENT_D/
   #      ├── child_d.ESS                          $CHILD_D/
   #      │   ├── child_f.IAB                         $CHILD_F1
   #      │   └── child_f.mKP                         $CHILD_F2
   #      ├── parent_f.IbA                         $PARENT_F1
   #      └── parent_f.lXM                         $PARENT_F2
   #
   # Don't need to explicitly clean up, as the temporary bats run dirs are
   # cleaned up after use.

   export PARENT_D="$(  mktemp -p "$BATS_RUN_TMPDIR" -d  'parent_d.XXX' )"
   export PARENT_F1="$( mktemp -p "$PARENT_D"            'parent_f.XXX' )"
   export PARENT_F2="$( mktemp -p "$PARENT_D"            'parent_f.XXX' )"

   export CHILD_D="$(  mktemp -p "$PARENT_D" -d  'child_d.XXX' )"
   export CHILD_F1="$( mktemp -p "$CHILD_D"      'child_f.XXX' )"
   export CHILD_F2="$( mktemp -p "$CHILD_D"      'child_f.XXX' )"
}


@test "raise parse_error if constrain occurs in a sub-file" {
   # Ideally I would've liked to have included this with the rest of the
   # exceptions, however I wanted to test in a real-world situation with
   # multiple files, rather than simply changing the .files prop.

   init_globals
   add_file "$PARENT_F1"

   echo "%include '${PARENT_F2}';"  > "$PARENT_F1"
   echo "%constrain [ '' ];"        > "$PARENT_F2"

   _parse
   run merge_includes

   assert_failure
   assert_output 'Parse Error: %constrain may not occur in a sub-file.'
}
