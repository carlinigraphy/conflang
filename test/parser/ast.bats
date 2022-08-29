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
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/declaration-empty.conf"
   )
   init_scanner ; scan ; parse

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
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/declaration.conf"
   )
   init_scanner ; scan ; parse

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


@test "declaration w/ boolean" {
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/boolean.conf"
   )
   init_scanner ; scan ; parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     'true'
   assert_equal  "${TYPEOF[NODE_6]}"  'boolean'
}


@test "declaration w/ integer" {
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/integer.conf"
   )
   init_scanner ; scan ; parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     '100'
   assert_equal  "${TYPEOF[NODE_6]}"  'integer'
}


@test "declaration w/ string" {
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/string.conf"
   )
   init_scanner ; scan ; parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     'string'
   assert_equal  "${TYPEOF[NODE_6]}"  'string'
}


@test "declaration w/ path" {
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/path.conf"
   )
   init_scanner ; scan ; parse

   local -n node='NODE_6'
   assert_equal  "${node[value]}"     'path'
   assert_equal  "${TYPEOF[NODE_6]}"  'path'
}


@test "declaration w/ fstring" {
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/fstring.conf"
   )
   init_scanner ; scan ; parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'string'
   assert_equal  "${node[value]}"     'before'

   local -n node='NODE_7'
   assert_equal  "${TYPEOF[NODE_6]}"  'string'
   assert_equal  "${node[value]}"     'after'
}


@test "declaration w/ fpath" {
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/ast/fpath.conf"
   )
   init_scanner ; scan ; parse

   local -n node='NODE_6'
   assert_equal  "${TYPEOF[NODE_6]}"  'path'
   assert_equal  "${node[value]}"     'before'

   local -n node='NODE_7'
   assert_equal  "${TYPEOF[NODE_6]}"  'path'
   assert_equal  "${node[value]}"     'after'
}


#@test "declaration w/ identifier" {
#   skip
#}
#
#
#@test "declaration w/ array with elements" {
#   skip
#}
#
#
#@test "declaration w/ array of arrays" {
#   skip
#}
#
#
#@test "declaration w/ array" {
#   skip
#}
#
#
#@test "declaration w/ unary" {
#   skip
#}
#
#
#@test "declaration w/ internal variable" {
#}
#
#
#@test "declaration w/ environment variable" {
#}
#
#
#@test "declaration w/ index" {
#}
#
#
#@test "declaration w/ typecast" {
#}
#
#
#@test "section declaration" {
#   skip
#}
#
#
#@test "section declaration, nested" }
#   skip
#}
#
#
#@test "include" {
#   skip
#}
#
#
#@test "exclude" {
#   skip
#}
