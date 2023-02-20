#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local SRC="${BATS_TEST_DIRNAME}/../../src"
   source "${SRC}/main"
   source "${SRC}/files.sh"
   source "${SRC}/errors.sh"
   source "${SRC}/parser.sh"

   export _LEXER_SH="${SRC}/lexer.sh"
   export F=$( mktemp "${BATS_TEST_TMPDIR}"/XXX ) 
}


@test "successful source, ./lib/lexer.sh" {
   source "$_LEXER_SH"
}


@test "fails with no input" {
   source "$_LEXER_SH"

   globals:init
   file:new
   run file:resolve

   assert_equal  "$status"  "${ERROR_CODE[missing_file]%%,*}"
   assert_output 'File Error(e12): missing or unreadable source file []'
}


@test "runs with empty file" {
   : 'Given an empty input file, should successfully lex, generating only the
      final EOF token when closing the file.'

   source "$_LEXER_SH"

   globals:init
   file:new
   file:resolve "$F"
   echo '' > "$F"

   lexer:init
   lexer:scan

   # Should have only an EOF token.
   assert [ ${#TOKENS[@]} -eq 1 ]

   local -n t="${TOKENS[0]}" 
   assert_equal "${t[type]}"  'EOF'
}
