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

   export F=$( mktemp "${BATS_TEST_TMPDIR}"/XXX ) 
}


@test "variable declaration, empty" {
   globals:init
   file:new
   file:resolve "$F"

   echo 'key;' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo 'key @str: "value";' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo 'key @list[str];' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo "_: true;" > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     'true'
   assert_equal  "${TYPEOF[NODE_8]}"  'boolean'
}


@test "declaration w/ integer" {
   globals:init
   file:new
   file:resolve "$F"

   echo '_: 100;' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     '100'
   assert_equal  "${TYPEOF[NODE_8]}"  'integer'
}


@test "declaration w/ string" {
   globals:init
   file:new
   file:resolve "$F"

   echo '_: "string";' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     'string'
   assert_equal  "${TYPEOF[NODE_8]}"  'string'
}


@test "declaration w/ path" {
   globals:init
   file:new
   file:resolve "$F"

   echo "_: 'path';" > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${node[value]}"     'path'
   assert_equal  "${TYPEOF[NODE_8]}"  'path'
}


@test "declaration w/ fstring" {
   globals:init
   file:new
   file:resolve "$F"

   echo '_: f"before{}after";' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo "_: f'before{}after';" > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo '_: [];' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local node='NODE_8'
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   assert_equal  "${TYPEOF[$node]}"  'list'
   assert_equal  "${#items_r[@]}"    0
}


@test "declaration w/ unary" {
   globals:init
   file:new
   file:resolve "$F"

   echo '_: -1;' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo '_: foo;' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'identifier'
   assert_equal  "${node[value]}"     'foo'
}


@test "declaration w/ environment variable" {
   globals:init
   file:new
   file:resolve "$F"

   echo '_: $ENV;' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local -n node='NODE_8'
   assert_equal  "${TYPEOF[NODE_8]}"  'env_var'
   assert_equal  "${node[value]}"     'ENV'
}


@test "declaration w/ index" {
   globals:init
   file:new
   file:resolve "$F"

   echo '_: [0][0];' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo '_: "to path" -> path;' > "$F"
   lexer:init
   lexer:scan

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
   globals:init
   file:new
   file:resolve "$F"

   echo '_ { }' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse

   local node='NODE_4'
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   assert_equal  "${TYPEOF[$node]}"  'decl_section'
   assert_equal  "${#items[@]}"      0
}
