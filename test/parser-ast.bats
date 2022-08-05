#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'
   source "${BATS_TEST_DIRNAME}"/../lib/errors.sh
   source "${BATS_TEST_DIRNAME}"/../lib/parser.sh
}


@test "empty variable declaration" {
   local -A TOKEN_0=([file]="0" [type]="IDENTIFIER" [lineno]="1" [colno]="1" [offset]="0" [value]="ident" )
   local -A TOKEN_1=([file]="0" [type]="SEMI"       [lineno]="1" [colno]="6" [offset]="5" [value]=";"     )
   local -A TOKEN_2=([file]="0" [type]="EOF"        [lineno]="2" [colno]="0" [offset]="6" [value]=""      )
   local -a TOKENS=(
      [0]="TOKEN_0"
      [1]="TOKEN_1"
      [2]="TOKEN_2"
   )

   parse

   local -A EXP=(
      [NODE_1]="identifier"         # NODE_1
      [NODE_2]="decl_section"       # NODE_2  (and NODE_3 holds the .items)
      [NODE_4]="identifier"         # NODE_4
      [NODE_5]="decl_variable"      # NODE_5
   )

   for idx in "${!EXP[@]}" ; do
      assert_equal "${TYPEOF[$idx]}"  "${EXP[$idx]}"
   done

   # The variable declaration, and typedef, should both be empty.
   local -n node_5="NODE_5"
   assert_equal "${node_5[expr]}"  ''
   assert_equal "${node_5[type]}"  ''
}


#@test "empty variable declaration w/ type" {
#   local -A TOKEN_0=([file]="0" [type]="IDENTIFIER" [lineno]="1" [colno]="1" [offset]="0" [value]="ident" )
#   local -A TOKEN_1=([file]="0" [type]="SEMI"       [lineno]="1" [colno]="6" [offset]="5" [value]=";"     )
#   local -A TOKEN_2=([file]="0" [type]="EOF"        [lineno]="2" [colno]="0" [offset]="6" [value]=""      )
#   local -a TOKENS=(
#      [0]="TOKEN_0"
#      [1]="TOKEN_1"
#      [2]="TOKEN_2"
#   )
#
#   parse
#
#   local -A EXP=(
#      [NODE_1]="identifier"         # NODE_1
#      [NODE_2]="decl_section"       # NODE_2  (and NODE_3 holds the .items)
#      [NODE_4]="identifier"         # NODE_4
#      [NODE_5]="decl_variable"      # NODE_5
#   )
#
#   for idx in "${!EXP[@]}" ; do
#      assert_equal "${TYPEOF[$idx]}"  "${EXP[$idx]}"
#   done
#
#   # The variable declaration, and typedef, should both be empty.
#   local -n node_5="NODE_5"
#   assert_equal "${node_5[expr]}"  ''
#   assert_equal "${node_5[type]}"  ''
#}


#@test "variable declaration w/ type and value" {
#   skip
#}
#
#
#@test "declaration w/ boolean" {
#   skip
#}
#
#
#@test "declaration w/ integer" {
#   skip
#}
#
#
#@test "declaration w/ string" {
#   skip
#}
#
#
#@test "declaration w/ path" {
#   skip
#}
#
#
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
#@test "include" {
#   skip
#}
#
#
#@test "exclude" {
#   skip
#}
#
#
#@test "context w/ tests" {
#   skip
#}
#
#
#@test "context w/ directives" {
#   skip
#}
#
#
#@test "typedef" {
#   skip
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
