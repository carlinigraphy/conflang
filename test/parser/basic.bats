#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local src="${BATS_TEST_DIRNAME}/../../src"
   source "${src}/main"
   source "${src}/locations.sh"
   source "${src}/lexer.sh"
   source "${src}/parser.sh"
   source "${src}/errors.sh"

   globals:init
   file:new
   file:resolve "/dev/stdin"
}


@test 'empty list' {
   lexer:init
   lexer:scan <<< '_: [];' 

   parser:init
   parser:parse

   local node='NODE_8'
   local -n node_r="$node"
   local -n node_items_r="${node_r[items]}"

   assert_equal "${TYPEOF[$node]}"     'list'
   assert_equal "${#node_items_r[@]}"  0
}


@test 'nested list' {
   lexer:init
   lexer:scan <<< '
      a1: [
         [
            []
         ]
      ];
   '

   parser:init
   parser:parse

   local a1='NODE_8'
   local -n a1_r="$a1"
   local -n a1_items_r="${a1_r[items]}"

   local a2="${a1_items_r[0]}"
   local -n a2_r="$a2"
   local -n a2_items_r="${a2_r[items]}"

   local a3="${a2_items_r[0]}"
   local -n a3_r="$a3"
   local -n a3_items_r="${a3_r[items]}"

   # Each item must be an list.
   assert_equal "${TYPEOF[$a1]}"  'list'
   assert_equal "${TYPEOF[$a2]}"  'list'
   assert_equal "${TYPEOF[$a3]}"  'list'

   # Each section should only contain a single sub-item, the nested section.
   # With the exception of the last, which is empty.
   assert_equal  "${#a1_items_r[@]}"  1
   assert_equal  "${#a2_items_r[@]}"  1
   assert_equal  "${#a3_items_r[@]}"  0
}


@test 'disallow assignment in lists' {
   lexer:init
   lexer:scan <<< '
      _: [
         key: value;
      ];
   '

   parser:init
   run parser:parse
   assert_failure
}


@test 'allow trailing comma' {
   lexer:init
   lexer:scan <<< "
      _: [
         '',
      ];
   "

   parser:init
   parser:parse

   local node='NODE_8'
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   # There should only be a single item, and no error thrown.
   assert_equal  "${TYPEOF[$node]}"  'list'
   assert_equal  "${#items_r[@]}"    1
}


@test 'nested section' {
   lexer:init
   lexer:scan <<< '
      s1 {
         s2 {
            s3 {}
         }
      }
   '


   parser:init
   parser:parse

   local s1='NODE_7'
   local -n s1_r="$s1"
   local -n s1_items_r="${s1_r[items]}"

   local s2="${s1_items_r[0]}"
   local -n s2_r="$s2"
   local -n s2_items_r="${s2_r[items]}"

   local s3="${s2_items_r[0]}"
   local -n s3_r="$s3"
   local -n s3_items_r="${s3_r[items]}"

   # Each item must be a section.
   assert_equal "${TYPEOF[$s1]}"  'decl_section'
   assert_equal "${TYPEOF[$s2]}"  'decl_section'
   assert_equal "${TYPEOF[$s3]}"  'decl_section'

   # Each section should only contain a single sub-item, the nested section.
   # With the exception of the last, which is empty.
   assert_equal  "${#s1_items_r[@]}"  1
   assert_equal  "${#s2_items_r[@]}"  1
   assert_equal  "${#s3_items_r[@]}"  0
}
