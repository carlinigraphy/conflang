#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local src="${BATS_TEST_DIRNAME}/../../src"
   source "${src}/main"
   source "${src}/lexer.sh"
   source "${src}/locations.sh"
   source "${src}/parser.sh"
   source "${src}/errors.sh"

   export F=$( mktemp "${BATS_TEST_TMPDIR}"/XXX ) 
   globals:init

   file:new
   file:resolve "$F"
}


# TODO: Expect `:' before expressions, add more of these. Check that any
#       characte which begins an expression has accurate error reporting.

@test "raise munch_error on unexpected token" {
   echo '_ (4);' > "$F"
   lexer:init
   lexer:scan

   parser:init
   run parser:parse

   assert_failure
   assert_output --partial 'Parse Error('   # Error base
   assert_output --partial "expecting \`:' before expression"
}


@test "raise parse_error on missing \`:' before expression" {
   local -a expressions=(
      "_ 'path';"
      '_ "string";'
      '_ true;'
      '_ false;'
      '_ $env;'
      '_ 1;'
      '_ -1;'
      '_ [ ];'
   )

   for expr in "${expressions[@]}" ; do
      echo "$expr" > "$F"
      lexer:init
      lexer:scan

      parser:init
      run parser:parse

      assert_failure
      assert_output --partial 'Parse Error('
      assert_output --partial "expecting \`:' before expression"
   done
}


@test "raise parse_error on missing \`;' after declaration, 1" {
   echo '_: ""' > "$F"
   lexer:init
   lexer:scan

   parser:init
   run parser:parse

   # Test with EOF following.
   assert_failure
   assert_output --partial 'Parse Error('
   assert_output --partial "expecting \`;' after declaration"
}


@test "raise parse_error on missing \`;' after declaration, 2" {
   echo '_: "" s{}' > "$F"
   lexer:init
   lexer:scan

   parser:init
   run parser:parse

   # Test with identifier following.
   assert_failure
   assert_output --partial 'Parse Error('
   assert_output --partial "expecting \`;' after declaration"
}


@test "raise parse_error on non-expression (NUD)" {
   local -a expressions=(
      '_: ->'
      '_: ;'
      '_: #EOF'
   )

   for expr in "${expressions[@]}" ; do
      echo "$expr" > "$F"
      lexer:init
      lexer:scan

      parser:init
      run parser:parse

      assert_failure
      assert_output --partial 'Parse Error('
      assert_output --partial "expecting an expression"
   done
}


@test "raise parse_error on include taking a non-path" {
   echo 'import "string";' > "$F"
   lexer:init
   lexer:scan

   parser:init
   run parser:parse

   assert_failure
   assert_output --partial 'Parse Error('
   assert_output --partial 'expecting import path'
}
