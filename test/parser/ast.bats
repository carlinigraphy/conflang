#!/usr/bin/bats
# vim:ft=sh

# Tests solely the basics of generating all AST tokens. They should be created
# with the appropriate type and value. Nothing more than an introductory test
# to catch basic error in the lexer/parser.

function setup {
   bats_load_library '/usr/lib/bats-assert/load.bash'
   bats_load_library '/usr/lib/bats-support/load.bash'

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


@test "variable declaration, empty" {
   lexer:init
   lexer:scan <<< 'key;'

   parser:init
   parser:parse

   local -A EXP=(
      [NODE_3]='identifier'
      [NODE_4]='decl_section'
      [NODE_6]='identifier'
      [NODE_7]='decl_variable'
   )

   for idx in "${!EXP[@]}" ; do
      assert_equal "${TYPEOF[$idx]}"  "${EXP[$idx]}"
   done

   # The variable declaration, and typedef, should both be empty.
   local -n node_r="NODE_7"
   assert_equal "${node_r[expr]}"  ''
   assert_equal "${node_r[type]}"  ''
}


@test "variable declaration, type and value" {
   lexer:init
   lexer:scan <<< 'key @str: "value";'

   parser:init
   parser:parse

   local -A EXP=(
      [NODE_3]='identifier' 
      [NODE_4]='decl_section' 
      [NODE_6]='identifier' 
      [NODE_7]='decl_variable' 
      [NODE_8]='identifier' 
      [NODE_9]='type' 
      [NODE_10]='string'
   )

   for idx in "${!EXP[@]}" ; do
      assert_equal "${TYPEOF[$idx]}"  "${EXP[$idx]}"
   done

   local -n node_r='NODE_7'
   assert_equal "${node_r[expr]}"  'NODE_10'
   assert_equal "${node_r[type]}"  'NODE_9'
}


@test "declaration w/ complex type" {
   lexer:init
   lexer:scan <<< 'key @list[str];' 

   parser:init
   parser:parse

   local -n typedef_r='NODE_9'
   local -n t_list_r="${typedef_r[kind]}"
   assert_equal "${t_list_r[value]}"   'list'

   local -n subtype_r="${typedef_r[subtype]}"
   local -n t_string_r="${subtype_r[kind]}"
   assert_equal "${t_string_r[value]}"  'str'
}


@test "declaration w/ boolean" {
   lexer:init
   lexer:scan <<< "_: true;" 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     'true'
   assert_equal  "${TYPEOF[NODE_8]}"  'boolean'
}


@test "declaration w/ integer" {
   lexer:init
   lexer:scan <<< '_: 100;' 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     '100'
   assert_equal  "${TYPEOF[NODE_8]}"  'integer'
}


@test "declaration w/ string" {
   lexer:init
   lexer:scan <<< '_: "string";' 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     'string'
   assert_equal  "${TYPEOF[NODE_8]}"  'string'
}


@test "declaration w/ path" {
   lexer:init
   lexer:scan <<< "_: 'path';" 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     'path'
   assert_equal  "${TYPEOF[NODE_8]}"  'path'
}


@test "declaration w/ fstring" {
   lexer:init
   lexer:scan <<< '_: f"before{}after";' 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'string'
   assert_equal  "${node[value]}"     'before'

   local -n node='NODE_9'
   assert_equal  "${TYPEOF[NODE_8]}"  'string'
   assert_equal  "${node[value]}"     'after'
}


@test "declaration w/ fpath" {
   lexer:init
   lexer:scan <<< "_: f'before{}after';" 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'path'
   assert_equal  "${node[value]}"     'before'

   local -n node='NODE_9'
   assert_equal  "${TYPEOF[NODE_8]}"  'path'
   assert_equal  "${node[value]}"     'after'
}


@test "declaration w/ list" {
   lexer:init
   lexer:scan <<< '_: [];' 

   parser:init
   parser:parse

   local node='NODE_8'
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   assert_equal  "${TYPEOF[$node]}"  'list'
   assert_equal  "${#items_r[@]}"    0
}


@test "declaration w/ unary" {
   lexer:init
   lexer:scan <<< '_: -1;' 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'unary'

   local -- right_name="${node[right]}"
   local -n right="${node[right]}"
   assert_equal  "${TYPEOF[$right_name]}"  'integer'
   assert_equal  "${right[value]}"          1
}


@test "declaration w/ identifier" {
   lexer:init
   lexer:scan <<< '_: foo;' 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'identifier'
   assert_equal  "${node[value]}"     'foo'
}


@test "declaration w/ environment variable" {
   lexer:init
   lexer:scan <<< '_: $ENV;' 

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'env_var'
   assert_equal  "${node[value]}"     'ENV'
}


@test "declaration w/ index" {
   lexer:init
   lexer:scan <<< '_: [0][0];' 

   parser:init
   parser:parse

   local node='NODE_11'
   local -n node_r="$node"

   local left="${node_r[left]}"
   local -n left_r="$left"

   local right="${node_r[right]}"
   local -n right_r="$right"

   assert_equal  "${TYPEOF[$node]}"   'index'
   assert_equal  "${TYPEOF[$left]}"   'list'
   assert_equal  "${TYPEOF[$right]}"  'integer'
}


@test "declaration w/ typecast" {
   lexer:init
   lexer:scan <<< '_: "to path" -> path;' 

   parser:init
   parser:parse

   local node='NODE_9'
   local -n node_r="$node"
   local type="${node_r[type]}"
   local expr="${node_r[expr]}"

   assert_equal  "${TYPEOF[$node]}"   'typecast'
   assert_equal  "${TYPEOF[$type]}"   'type'
   assert_equal  "${TYPEOF[$expr]}"   'string'
}


@test "section declaration" {
   lexer:init
   lexer:scan <<< '_ { }' 

   parser:init
   parser:parse

   local node='NODE_4'
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   assert_equal  "${TYPEOF[$node]}"  'decl_section'
   assert_equal  "${#items[@]}"      0
}
