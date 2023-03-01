#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local src="${BATS_TEST_DIRNAME}/../../src"
   export _LEXER_SH="${src}/lexer.sh"
   export _PARSER_SH="${src}/parser.sh"

   source "${src}/main"
   source "${src}/errors.sh"
   source "${src}/locations.sh"

   export F=$( mktemp "${BATS_TEST_TMPDIR}"/XXX ) 
}


@test "successful source, ./lib/parser.sh" {
   source "$_PARSER_SH"
}


@test "runs with only EOF token" {
   : 'While the parser should fail given *NO* tokens in the input, it should
      successfully parse an empty file (only EOF token).'

   source "$_PARSER_SH"

   local -A TOKEN_0=( [type]='EOF' [value]='' )
   local -a TOKENS=( 'TOKEN_0' )

   parser:init
   run parser:parse

   assert_success
}


@test "lexer -> parser with empty file" {
   : 'More complete test, starting from the lexer, transitioning into the
      parser. Testing handoff.'

   source "$_LEXER_SH"
   source "$_PARSER_SH"

   globals:init
   file:new
   file:resolve "$F"

   echo '' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse
}


@test "lexer -> parser with simple data" {
   : 'Must check the lexer successfully hands off everything to the parser.
      and no additional global vars/functions are unspecified'

   source "$_LEXER_SH"
   source "$_PARSER_SH"

   globals:init
   file:new
   file:resolve "$F"

   echo 'this @str: "that";' > "$F"
   lexer:init
   lexer:scan

   parser:init
   parser:parse
}
