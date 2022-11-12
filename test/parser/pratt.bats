#!/usr/bin/bats
# vim:ft=sh
#
# Specifically for testing the functionality of the Pratt parser. We're
# covering all the regular NUD operations in ./ast.bats, really only need to
# test more advanced maneuvers. Multiple concatenations in a single string,
# operator precedence for typecasts that have a complex left expression, etc.

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/parser.sh"
   source "${LIBDIR}/errors.sh"

   function parse_from_str {
      lexer:init
      lexer:scan <<< "$1"

      parser:init
      parser:parse
   }
   export -f parse_from_str
}

@test "operator precedence, typecast" {
   # Typecast should be of the lowest precedence. There is not an addition
   # operator, but assuming there was, we'd want the following expression...
   #> "string/path/1" + "string/path/2" -> path;
   # ...to be read as...
   #> ("string/path/1" + "string/path/2") -> path;

   # Sadly arrays cannot be exported. There is no support in bash to export an
   # array into the environment. v sad bruh.
   local -a FILES=( /dev/stdin )

   # This string should represent: (STR + %_ + STR + %_ + STR) -> path
   parse_from_str '_: "{%_}{%_}" -> path;'
}
