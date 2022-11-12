#!/usr/bin/bats
# vim:ft=sh

# Tests solely the basics of generating all AST tokens. They should be created
# with the appropriate type and value. Nothing more than an introductory test
# to catch basic error in the lexer/parser.

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/errors.sh"
}

@test "variable declaration, empty" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< 'key;'

   init_parser
   parse

   local -A EXP=(
      [NODE_1]='identifier'
      [NODE_2]='decl_section'
      [NODE_4]='identifier'
      [NODE_5]='decl_variable'
   )

   for idx in "${!EXP[@]}" ; do
      assert_equal "${TYPEOF[$idx]}"  "${EXP[$idx]}"
   done

   # The variable declaration, and typedef, should both be empty.
   local -n node_5="NODE_5"
   assert_equal "${node_5[expr]}"  ''
   assert_equal "${node_5[type]}"  ''
}


@test "variable declaration, type and value" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< 'key (str): "value";'

   init_parser
   parse

   local -A EXP=(
      [NODE_1]='identifier' 
      [NODE_2]='decl_section' 
      [NODE_4]='identifier' 
      [NODE_5]='decl_variable' 
      [NODE_6]='identifier' 
      [NODE_7]='typedef' 
      [NODE_8]='string'
   )

   for idx in "${!EXP[@]}" ; do
      assert_equal "${TYPEOF[$idx]}"  "${EXP[$idx]}"
   done

   local -n node_5='NODE_5'
   assert_equal "${node_5[expr]}"  'NODE_8'
   assert_equal "${node_5[type]}"  'NODE_7'
}


@test "declaration w/ complex type" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< 'key (array:str);'

   init_parser
   parse

   local -n typedef='NODE_7'
   local -n t_array="${typedef[kind]}"
   assert_equal "${t_array[value]}"   'array'

   local -n subtype="${typedef[subtype]}"
   local -n t_string="${subtype[kind]}"
   assert_equal "${t_string[value]}"  'str'
}


@test "declaration w/ boolean" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< "_: true;"

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     'true'
   assert_equal  "${TYPEOF[NODE_6]}"  'boolean'
}


@test "declaration w/ integer" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: 100;'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     '100'
   assert_equal  "${TYPEOF[NODE_6]}"  'integer'
}


@test "declaration w/ string" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: "string";'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     'string'
   assert_equal  "${TYPEOF[NODE_6]}"  'string'
}


@test "declaration w/ path" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< "_: 'path';"

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     'path'
   assert_equal  "${TYPEOF[NODE_6]}"  'path'
}


@test "declaration w/ fstring" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: f"before{}after";'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'string'
   assert_equal  "${node[value]}"     'before'

   local -n node='NODE_7'
   assert_equal  "${TYPEOF[NODE_6]}"  'string'
   assert_equal  "${node[value]}"     'after'
}


@test "declaration w/ fpath" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< "_: f'before{}after';"

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'path'
   assert_equal  "${node[value]}"     'before'

   local -n node='NODE_7'
   assert_equal  "${TYPEOF[NODE_6]}"  'path'
   assert_equal  "${node[value]}"     'after'
}


@test "declaration w/ array" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: [];'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'array'
   assert_equal  "${#node[@]}"        0
}


@test "declaration w/ unary" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: -1;'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'unary'

   local -- right_name="${node[right]}"
   local -n right="${node[right]}"
   assert_equal  "${TYPEOF[$right_name]}"  'integer'
   assert_equal  "${right[value]}"          1
}


@test "declaration w/ identifier" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: foo;'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'identifier'
   assert_equal  "${node[value]}"     'foo'
}


@test "declaration w/ environment variable" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: $ENV;'

   init_parser
   parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'env_var'
   assert_equal  "${node[value]}"     'ENV'
}


@test "declaration w/ index" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: [0][0];'

   init_parser
   parse

   local -- node_name='NODE_8'
   local -n node="$node_name"

   local -- left_name="${node[left]}"
   local -n left="$left_name"

   local -- right_name="${node[right]}"
   local -n right="$right_name"

   assert_equal  "${TYPEOF[$node_name]}"   'index'
   assert_equal  "${TYPEOF[$left_name]}"   'array'
   assert_equal  "${TYPEOF[$right_name]}"  'integer'
}


@test "declaration w/ typecast" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_: "to path" -> path;'

   init_parser
   parse

   local -- node_name='NODE_7'
   local -n node="$node_name"
   local -- typedef="${node[typedef]}"
   local -- expr="${node[expr]}"

   assert_equal  "${TYPEOF[$node_name]}"  'typecast'
   assert_equal  "${TYPEOF[$typedef]}"    'typedef'
   assert_equal  "${TYPEOF[$expr]}"       'string'
}


@test "section declaration" {
   local -a FILES=( /dev/stdin )

   init_scanner
   scan <<< '_ { }'

   init_parser
   parse

   local -- node_name='NODE_5'
   local -n node="$node_name"
   local -n items="${node[items]}"

   assert_equal  "${TYPEOF[$node_name]}"  'decl_section'
   assert_equal  "${#items[@]}"  0
}
