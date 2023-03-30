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

   globals:init
   file:new
   file:resolve "/dev/stdin"
}


@test "raise munch_error on unexpected token" {
   lexer:init
   lexer:scan <<< '_ (4);' 

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
      lexer:init
      lexer:scan <<< "$expr"

      parser:init
      run parser:parse

      assert_failure
      assert_output --partial 'Parse Error('
      assert_output --partial "expecting \`:' before expression"
   done
}


@test "raise parse_error on missing \`;' after declaration, 1" {
   lexer:init
   lexer:scan <<< '_: ""' 

   parser:init
   run parser:parse

   # Test with EOF following.
   assert_failure
   assert_output --partial 'Parse Error('
   assert_output --partial "expecting \`;' after declaration"
}


@test "raise parse_error on missing \`;' after declaration, 2" {
   lexer:init
   lexer:scan <<< '_: "" s{}' 

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
      lexer:init
      lexer:scan <<< "$expr"

      parser:init
      run parser:parse

      assert_failure
      assert_output --partial 'Parse Error('
      assert_output --partial "expecting an expression"
   done
}


@test "raise parse_error on include taking a non-path" {
   lexer:init
   lexer:scan <<< 'import "string";' 

   parser:init
   run parser:parse

   assert_failure
   assert_output --partial 'Parse Error('
   assert_output --partial 'expecting import path'
}
