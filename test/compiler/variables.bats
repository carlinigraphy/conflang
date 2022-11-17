#!/bin/bats
# vim:ft=bash

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/../bin/confc"
   source "${LIBDIR}/errors.sh"
   source "${LIBDIR}/utils.sh"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/semantics.sh"
   source "${LIBDIR}/compiler.sh"
}


@test 'resolve primitive identifier' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '
      _str:  "string";
      _int:  1;
      _bool: true;

      str_ref:  _str;
      int_ref:  _int;
      bool_ref: _bool;
   '
   utils:eval

   # %inline container
   declare -n d1='_DATA_1'
   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )

   assert_equal "$type_d1"      '-A'
   assert_equal "${#d1[@]}"     6

   assert_equal "${d1[_str]}"   "${d1[str_ref]}"
   assert_equal "${d1[_int]}"   "${d1[int_ref]}"
   assert_equal "${d1[_bool]}"  "${d1[bool_ref]}"
}


@test 'resolve complex identifier' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '
      _array: [
         "string",
      ];
      array_ref:   _array;
      array_ref_0: _array[0];
   '
   utils:eval

   declare -n d1='_DATA_1'
   declare -n d2='_DATA_2'
   declare -n d3='_DATA_3'

   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"    '-A'
   assert_equal "${#d1[@]}"   3

   declare -n a1="${d1[_array]}"
   assert_equal "${a1[@]}"  "${d2[@]}"    # array    == array_ref
   assert_equal "${a1[0]}"  "${d3}"       # array[0] == array_ref_0
}


@test 'resolve nested identifier' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '
      section {
         _array: [
            "string",
         ];
      }

      array_ref:   section._array;
      array_ref_0: section._array[0];
   '
   utils:eval

   declare -p ${!_DATA_*} 1>&3 ; skip

   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"    '-A'
   assert_equal "${#d1[@]}"   3

   declare -n a1="${d1[_array]}"
   assert_equal "${a1[@]}"  "${d2[@]}"    # array    == array_ref
   assert_equal "${a1[0]}"  "${d3}"       # array[0] == array_ref_0
}


@test 'resolve environment variable' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< 'home: $HOME;'
   utils:eval

   # %inline container
   declare -n d1='_DATA_1'
   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"      '-A'
   assert_equal "${#d1[@]}"     1
   assert_equal "${d1[home]}"   "$HOME"
}


@test 'resolve stomped environment variable' {
   init_globals
   INPUT=/dev/stdin

   declare -- home="$HOME"
   declare -g HOME='beepboop'

   utils:parse <<< 'home: $HOME;'
   utils:eval

   # %inline container
   declare -n d1='_DATA_1'
   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"      '-A'
   assert_equal "${#d1[@]}"     1
   assert_equal "${d1[home]}"   "$home"
}


@test 'fail on missing environment variable' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '
      _: $_92718c1730c3b90eb8ac688e47b14598;
   '
   run utils:eval

   assert_failure
   assert_equal "$status"  "${EXIT_STATUS[missing_env_var]}"
}


@test 'resolve unary expression' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< 'n: -2;'
   utils:eval

   # %inline container
   declare -n d1='_DATA_1'
   type_d1=$( declare -p _DATA_1 | awk '{print $2}' )
   assert_equal "$type_d1"   '-A'
   assert_equal "${#d1[@]}"  1
   assert_equal "${d1[n]}"   "-2"
}
