#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/errors.sh"
}


@test 'empty array' {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: [];'
   parse

   local -- node_name='NODE_6'
   local -n node="$node_name"

   assert_equal "${TYPEOF[$node_name]}"  'array'
   assert_equal "${#node[@]}"  0
}


@test 'nested array' {
   local -a FILES=( /dev/stdin )
   local input='
      a1: [
         [
            []
         ]
      ];
   '

   init_scanner
   scan <<< "$input"
   parse

   local -- a1_name='NODE_6'
   local -n a1="$a1_name"

   local -- a2_name="${a1[0]}"
   local -n a2="$a2_name"

   local -- a3_name="${a2[0]}"
   local -n a3="$a3_name"

   # Each item must be an array.
   assert_equal "${TYPEOF[$a1_name]}"  'array'
   assert_equal "${TYPEOF[$a2_name]}"  'array'
   assert_equal "${TYPEOF[$a3_name]}"  'array'

   # Each section should only contain a single sub-item, the nested section.
   # With the exception of the last, which is empty.
   assert_equal  "${#a1[@]}"  1
   assert_equal  "${#a2[@]}"  1
   assert_equal  "${#a3[@]}"  0
}


@test 'disallow assignment in arrays' {
   local -a FILES=( /dev/stdin )
   local input='
      _: [
         key: value;
      ];
   '

   init_scanner
   scan <<< "$input"

   run parse
   assert_failure
}


@test 'allow trailing comma' {
   local -a FILES=( /dev/stdin )
   local input="
      _: [
         '',
      ];
   "

   init_scanner
   scan <<< "$input"
   parse

   local -- node_name='NODE_6'
   local -n items="$node_name"

   # There should only be a single item, and no error thrown.
   assert_equal  "${TYPEOF[$node_name]}"  'array'
   assert_equal  "${#items[@]}"  1
}


@test 'nested section' {
   local -a FILES=( /dev/stdin )
   local input='
      s1 {
         s2 {
            s3 {}
         }
      }
   '

   init_scanner
   scan <<< "$input"
   parse

   local -- s1_name='NODE_5'
   local -n s1="$s1_name"
   local -n i1="${s1[items]}"

   local -- s2_name="${i1[0]}"
   local -n s2="$s2_name"
   local -n i2="${s2[items]}"

   local -- s3_name="${i2[0]}"
   local -n s3="$s3_name"
   local -n i3="${s3[items]}"

   # Each item must be a section.
   assert_equal "${TYPEOF[$s1_name]}"  'decl_section'
   assert_equal "${TYPEOF[$s2_name]}"  'decl_section'
   assert_equal "${TYPEOF[$s3_name]}"  'decl_section'

   # Each section should only contain a single sub-item, the nested section.
   # With the exception of the last, which is empty.
   assert_equal  "${#i1[@]}"  1
   assert_equal  "${#i2[@]}"  1
   assert_equal  "${#i3[@]}"  0
}
