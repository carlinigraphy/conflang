#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/errors.sh"
   source "${LIBDIR}/utils.sh"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/semantics.sh"
   source "${LIBDIR}/compiler.sh"
}


@test 'create global symbol table' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< ''
   utils:eval

   assert [ "${GLOBALS[%inline]}" ]

   local t_basic=(
      any
      fn
      int
      str
      bool
      path
   )
   local t_complex=(
      array
   )

   for t in "${t_basic[@]}" ; do
      symbol_name="${GLOBALS[$t]}"
      assert [ "$symbol_name" ]

      declare -n meta_symbol="$symbol_name"
      declare -n meta_type="${meta_symbol[type]}"
      declare -n type="${meta_type[subtype]}"

      assert [ ! "${type[subtype]}" ]
   done

   for t in "${t_complex[@]}" ; do
      symbol_name="${GLOBALS[$t]}"
      assert [ "$symbol_name" ]

      declare -n meta_symbol="$symbol_name"
      declare -n meta_type="${meta_symbol[type]}"
      declare -n type="${meta_type[subtype]}"

      assert [ "${type[subtype]+_}" ]
   done
}


@test 'create expected simple types' {
   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '
      _;
      int   (int);
      str   (str);
      bool  (bool);
      path  (path);
   '
   utils:eval

   declare -n s_inline="${GLOBALS[%inline]}"
   declare -n symtab="${s_inline[symtab]}"

   declare -n s_int="${symtab[_]}"
   declare -n t_int="${s_int[type]}"
   assert_equal "${t_int[kind]}"  'ANY'

   declare -n s_int="${symtab[int]}"
   declare -n t_int="${s_int[type]}"
   assert_equal "${t_int[kind]}"  'INTEGER'

   declare -n s_str="${symtab[str]}"
   declare -n t_str="${s_str[type]}"
   assert_equal "${t_str[kind]}"  'STRING'

   declare -n s_bool="${symtab[bool]}"
   declare -n t_bool="${s_bool[type]}"
   assert_equal "${t_bool[kind]}"  'BOOLEAN'

   declare -n s_path="${symtab[path]}"
   declare -n t_path="${s_path[type]}"
   assert_equal "${t_path[kind]}"  'PATH'
}


@test 'create complex types' {
   skip 'Turns out complex types do not seem to be making a subtype. Neat.'

   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '
      a1 (array:str);
      a2 (array:array:str);
   '
   utils:eval

   declare -n s_inline="${GLOBALS[%inline]}"
   xeclare -n symtab="${s_inline[symtab]}"

   declare -n s_a1="${symtab[a1]}"
   declare -n t_a1="${s_a1[type]}"
   declare -n subtype="${t_a1[subtype]}"
   assert_equal "${t_a1[kind]}"     'ARRAY'
   assert_equal "${subtype[kind]}"  'STRING'

   declare -n s_a2="${symtab[a2]}"
   declare -n t_a2="${s_a2[type]}"
   declare -n subtype="${t_a2[subtype]}"
   declare -n subsub="${subtype[subtype]}"
   assert_equal "${t_a2[kind]}"     'ARRAY'
   assert_equal "${subtype[kind]}"  'ARRAY'
   assert_equal "${subsub[kind]}"   'STRING'
}


@test 'disallow int w/ subtype' {
   skip 'Need to address subtypes, they are not working as intended.'

   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '_ (int:int);'
   run utils:eval

   assert_failure
}


@test 'disallow str w/ subtype' {
   skip 'Need to address subtypes, they are not working as intended.'

   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '_ (str:int);'
   run utils:eval

   assert_failure
}


@test 'disallow bool w/ subtype' {
   skip 'Need to address subtypes, they are not working as intended.'

   init_globals
   INPUT=/dev/stdin

   utils:parse <<< '_ (bool:int);'
   run utils:eval

   assert_failure
}


@test 'typecast overwrites expression type' {
   skip
}
