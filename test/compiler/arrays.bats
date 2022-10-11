#!/bin/bats
# vim:ft=bash

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/errors.sh"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/semantics.sh"
   source "${LIBDIR}/compiler.sh"
   source "${LIBDIR}/utils.sh"
}


@test 'empty array -> empty indexed array' {
   init_globals
   INPUT=/dev/stdin

   do_parse <<< 'array: [];'
   do_compile

   # %inline container
   declare -n d1='_DATA_1'
   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"      '-A'
   assert_equal "${#d1[@]}"     1
   assert_equal "${d1[array]}"  '_DATA_2'

   declare -n d2='_DATA_2'
   type_d2=$( declare -p _DATA_2 | awk '{print $2}' )
   assert_equal "$type_d2"   '-a'
   assert_equal "${#d2[@]}"  0
}


@test 'nested array -> nested indexed array' {
   init_globals
   INPUT=/dev/stdin

   do_parse <<< 'array: [[]];'
   do_compile

   # %inline container
   declare -n d1='_DATA_1'
   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"      '-A'
   assert_equal "${#d1[@]}"     1
   assert_equal "${d1[array]}"  '_DATA_2'

   declare -n d2='_DATA_2'
   type_d2=$( declare -p _DATA_2 | awk '{print $2}' )
   assert_equal "$type_d2"   '-a'
   assert_equal "${#d2[@]}"  1
   assert_equal "${d2[@]}"   '_DATA_3'

   declare -n d3='_DATA_3'
   type_d3=$( declare -p _DATA_3 | awk '{print $2}' )
   assert_equal "$type_d3"  '-a'
   assert_equal "${#d3[@]}"  0
}
