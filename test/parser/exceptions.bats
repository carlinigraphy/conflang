#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/errors.sh"

   function parse_from_str {
      init_scanner
      scan <<< "$1"

      init_parser
      parse
   }
   export -f parse_from_str
}


@test "raise syntax_error on ERROR token" {
   local -a FILES=( /dev/stdin )
   run parse_from_str '&'

   assert_failure
   assert_output --regexp '^Syntax Error: \[[0-9]+:[0-9]+\]'   # Error base
   assert_output          "Syntax Error: [1:1] \`&'"           # Specific text.
}


@test "raise munch_error on unexpected token" {
   local -a FILES=( /dev/stdin )
   run parse_from_str '_ (4);'

   assert_failure
   assert_output --regexp  '^Parse Error: \[[0-9]+:[0-9]+\]'   # Error base
   assert_output --partial "expected identifier, received integer"
}


@test "raise parse_error on missing \`:' before expression" {
   local -a FILES=( /dev/stdin )

   local -a expressions=(
      [0]="_ 'path';"      [1]='_ "string";'
      [2]='_ true;'        [3]='_ false;'
      [4]='_ $env;'        [5]='_ %int;'
      [6]='_ 1;'           [7]='_ -1;'
      [8]='_ [ ];'
   )

   for expr in "${expressions[@]}" ; do
      run parse_from_str "$expr"
      assert_failure
      assert_output --regexp  '^Parse Error: '
      assert_output --partial "expecting \`:' before expression"
   done
}


@test "raise parse_error on missing \`;' after declaration" {
   local -a FILES=( /dev/stdin )

   # Test with EOF following.
   run parse_from_str  '_: ""'
   assert_failure
   assert_output --regexp  '^Parse Error: '
   assert_output --partial "Expecting \`;' after declaration"

   # Test with identifier following.
   run parse_from_str  '_: "" s{}'
   assert_failure
   assert_output --regexp  '^Parse Error: '
   assert_output --partial "Expecting \`;' after declaration"
}


@test "raise parse_error on non-expression (NUD)" {
   local -a FILES=( /dev/stdin )
   local -a expressions=(
      '_: s;'
      '_: ->'
      '_: ;'
      '_: #EOF'
   )

   for expr in "${expressions[@]}" ; do
      run parse_from_str "$expr"
      assert_failure
      assert_output --regexp  '^Parse Error: '
      assert_output --partial "not an expression"
   done
}
