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


@test "successful source, ./conflang" {
   source "$conflang"
}


@test "include absolute path to file from root" {
   source "$conflang"

   echo "%include '${PARENT_F2}';" > "$PARENT_F1"
   echo '_{}'                      > "$PARENT_F2"

   _init_globals
   add_file "$PARENT_F1"

   _parse
   assert_equal "${#FILES[@]}"       1
   assert_equal "${FILES[-1]}"       "$PARENT_F1"

   # Just to make sure.
   assert_equal "${#CONSTRAINTS[@]}" 0

   local -n include="${INCLUDES[0]}"
   assert_equal "${#INCLUDES[@]}"    1
   assert_equal "${include[path]}"   "$PARENT_F2"

   # Save ref to parent's root node.
   local root1="$ROOT"

   merge_includes
   assert_equal "${#FILES[@]}"       2
   assert_equal "${FILES[-1]}"       "$PARENT_F2"

   # Save ref to child's root node.
   local root2="$ROOT"

   assert_equal "$root1"  'NODE_2'
   assert_equal "${TYPEOF[$root1]}"  'decl_section'

   assert_equal "$root2"  'NODE_6'
   assert_equal "${TYPEOF[$root2]}"  'decl_section'
}


@test "include relative path to file, same dir" {
   source "$conflang"

   echo "%include '$(basename ${PARENT_F2})';" > "$PARENT_F1"
   echo '_{}' > "$PARENT_F2"

   _init_globals
   add_file "$PARENT_F1"

   _parse
   assert_equal "${#FILES[@]}"       1
   assert_equal "${FILES[-1]}"       "$PARENT_F1"

   # Just to make sure.
   assert_equal "${#CONSTRAINTS[@]}" 0

   local -n include="${INCLUDES[0]}"
   assert_equal "${#INCLUDES[@]}"    1
   assert_equal "${include[path]}"   "${PARENT_F2##*/}"
   # Specifically trying to use a different method here to determine the base
   # name of the file, rather than $(basename). The same method may cause me to
   # accidentally get the same incorrect value two times. This gives less of a
   # chance than that.

   # Save ref to parent's root node.
   local root1="$ROOT"

   merge_includes
   assert_equal "${#FILES[@]}"       2
   assert_equal "${FILES[-1]}"       "$PARENT_F2"

   # Save ref to child's root node.
   local root2="$ROOT"

   assert_equal "$root1"  'NODE_2'
   assert_equal "${TYPEOF[$root1]}"  'decl_section'

   assert_equal "$root2"  'NODE_6'
   assert_equal "${TYPEOF[$root2]}"  'decl_section'
}


@test "include relative path to file, dir down" {
   source "$conflang"

   # Relative path to the child file, through the child directory.
   local rela_child="./${CHILD_D##*/}/${CHILD_F1##*/}"
   echo "%include '${rela_child}';" > "$PARENT_F1"
   echo '_{}' > "$CHILD_F1"

   _init_globals
   add_file "$PARENT_F1"

   _parse
   assert_equal "${#FILES[@]}"       1
   assert_equal "${FILES[-1]}"       "$PARENT_F1"

   # Just to make sure.
   assert_equal "${#CONSTRAINTS[@]}" 0

   local -n include="${INCLUDES[0]}"
   assert_equal "${#INCLUDES[@]}"    1
   assert_equal "${include[path]}"   "${rela_child}"

   # Save ref to parent's root node.
   local root1="$ROOT"

   merge_includes
   assert_equal "${#FILES[@]}"       2
   assert_equal "${FILES[-1]}"       "$CHILD_F1"

   # Save ref to child's root node.
   local root2="$ROOT"

   assert_equal "$root1"  'NODE_2'
   assert_equal "${TYPEOF[$root1]}"  'decl_section'

   assert_equal "$root2"  'NODE_6'
   assert_equal "${TYPEOF[$root2]}"  'decl_section'
}


@test "include relative path to file, dir up" {
   source "$conflang"

   # Relative path to the child file, through the child directory.
   echo "%include '../${PARENT_F1##*/}';" > "$CHILD_F1"
   echo 'key;' > "$PARENT_F1"

   _init_globals
   add_file "$CHILD_F1"

   _parse
   assert_equal "${#FILES[@]}"       1
   assert_equal "${FILES[-1]}"       "$CHILD_F1"

   # Just to make sure.
   assert_equal "${#CONSTRAINTS[@]}" 0

   local -n include="${INCLUDES[0]}"
   assert_equal "${#INCLUDES[@]}"    1
   assert_equal "${include[path]}"   "../${PARENT_F1##*/}"

   # Save ref to parent's root node.
   local root1="$ROOT"

   merge_includes
   assert_equal "${#FILES[@]}"       2
   assert_equal "${FILES[-1]}"       "$PARENT_F1"

   # Save ref to child's root node.
   local root2="$ROOT"

   assert_equal "$root1"  'NODE_2'
   assert_equal "${TYPEOF[$root1]}"  'decl_section'

   assert_equal "$root2"  'NODE_6'
   assert_equal "${TYPEOF[$root2]}"  'decl_section'

   # Test that the child's root was indeed solely the variable declaration.
   local -n section="$root2"
   local -n items="${section[items]}"
   assert_equal "${#items[@]}" 1

   local -- decl_p="${items[0]}"
   local -n decl="$decl_p"
   assert_equal "${TYPEOF[${items[0]}]}"  'decl_variable'

   # And likewise confirm that the %inline section of the parent's root contains
   # the included variable declaration.
   local -n section="$root1"
   local -n items="${section[items]}"
   assert_equal "${#items[@]}" 1

   local -- decl_c="${items[0]}"
   local -n decl="$decl_p"
   assert_equal "${TYPEOF[${items[0]}]}"  'decl_variable'

   # The actual declaration node should be the same NODE_$n.
   assert_equal "$decl_p"  "$decl_c"
}


@test "include from section" {
   source "$conflang"

   echo "_{ %include '${CHILD_F1}'; }" > "$PARENT_F1"
   echo 'key;' > "$CHILD_F1"

   _init_globals
   add_file "$PARENT_F1"

   _parse
   assert_equal "${#FILES[@]}"       1
   assert_equal "${FILES[-1]}"       "$PARENT_F1"

   # Just to make sure.
   assert_equal "${#CONSTRAINTS[@]}" 0

   local -n include="${INCLUDES[0]}"
   assert_equal "${#INCLUDES[@]}"    1
   assert_equal "${include[path]}"   "${CHILD_F1}"

   # Save ref to parent's root node.
   local root1="$ROOT"

   merge_includes
   assert_equal "${#FILES[@]}"       2
   assert_equal "${FILES[-1]}"       "$CHILD_F1"

   # Save ref to child's root node.
   local root2="$ROOT"

   assert_equal "$root1"  'NODE_2'
   assert_equal "${TYPEOF[$root1]}"  'decl_section'

   assert_equal "$root2"  'NODE_9'
   assert_equal "${TYPEOF[$root2]}"  'decl_section'

   # Test that the child's root was indeed solely the variable declaration.
   local -n section="$root2"
   local -n items="${section[items]}"
   assert_equal "${#items[@]}" 1

   local -- decl_p="${items[0]}"
   local -n decl="$decl_p"
   assert_equal "${TYPEOF[$decl_p]}"  'decl_variable'

   # And likewise confirm that the %inline section of the parent's root contains
   # the included variable declaration under its subsection.
   local -n section="$root1"
   local -n items="${section[items]}"
   assert_equal "${#items[@]}" 1

   # Descend down into `_{...}` section.
   local -n subsection="${items[0]}"
   local -n items="${subsection[items]}"

   local -- decl_c="${items[0]}"
   local -n decl="$decl_p"
   assert_equal "${TYPEOF[$decl_p]}"  'decl_variable'

   # The actual declaration node should be the same NODE_$n. All of the above
   # was really for us to just end up here.
   assert_equal "$decl_p"  "$decl_c"
}


@test "include from subsection" {
   source "$conflang"

   # Relative path to the child file, through the child directory.
   echo "_{ _{ %include '$CHILD_F1'; }}" > "$PARENT_F1"
   echo 'key;' > "$CHILD_F1"

   _init_globals
   add_file "$PARENT_F1"

   _parse
   assert_equal "${#FILES[@]}"       1
   assert_equal "${FILES[-1]}"       "$PARENT_F1"

   # Just to make sure.
   assert_equal "${#CONSTRAINTS[@]}" 0

   local -n include="${INCLUDES[0]}"
   assert_equal "${#INCLUDES[@]}"    1
   assert_equal "${include[path]}"   "$CHILD_F1"

   # Save ref to parent's root node.
   local root1="$ROOT"

   merge_includes
   assert_equal "${#FILES[@]}"       2
   assert_equal "${FILES[-1]}"       "$CHILD_F1"

   # Save ref to child's root node.
   local root2="$ROOT"

   assert_equal "$root1"  'NODE_2'
   assert_equal "${TYPEOF[$root1]}"  'decl_section'

   assert_equal "$root2"  'NODE_12'
   assert_equal "${TYPEOF[$root2]}"  'decl_section'

   # Test that the child's root was indeed solely the variable declaration.
   local -n section="$root2"
   local -n items="${section[items]}"
   assert_equal "${#items[@]}" 1

   local -- decl_p="${items[0]}"
   local -n decl="$decl_p"
   assert_equal "${TYPEOF[$decl_p]}"  'decl_variable'

   # And likewise confirm that the %inline section of the parent's root contains
   # the included variable declaration under its subsection.
   local -n section="$root1"
   local -n items="${section[items]}"
   assert_equal "${#items[@]}" 1

   # Descend down into `_{...}` section.
   local -n subsection="${items[0]}"
   local -n items="${subsection[items]}"

   # And again into the subsection.
   local -n subsubsection="${items[0]}"
   local -n items="${subsubsection[items]}"

   local -- decl_c="${items[0]}"
   local -n decl="$decl_p"
   assert_equal "${TYPEOF[$decl_p]}"  'decl_variable'

   # The actual declaration node should be the same NODE_$n. All of the above
   # was really for us to just end up here.
   assert_equal "$decl_p"  "$decl_c"
}


@test "raise parse_error if constrain occurs in a sub-file" {
   # Ideally I would've liked to have included this with the rest of the
   # exceptions, however I wanted to test in a real-world situation with
   # multiple files, rather than simply changing the .files prop.

   source "$conflang"

   _init_globals
   add_file "$PARENT_F1"

   echo "%include '${PARENT_F2}';"  > "$PARENT_F1"
   echo "%constrain [ '' ];"        > "$PARENT_F2"

   _parse
   run merge_includes

   assert_failure
   assert_output 'Parse Error: %constrain may not occur in a sub-file.'
}
