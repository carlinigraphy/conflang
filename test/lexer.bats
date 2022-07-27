#!/usr/bin/env bats

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   # Lexer prerequisites from calling file/function:

   export _lexer=$( realpath "${BATS_TEST_DIRNAME}"/../lib/lexer.sh )
   export _lexer_files="${BATS_TEST_DIRNAME}"/lexer_files/keywords.conf
}

@test "lexer fails with no input" { skip; }

@test "lexer runs with empty file" { skip; }

@test "lexer correctly identifies keywords" {
   FILES+=( "${_lexer_files}" )   
   run 'share/lexer_prereqs.bash'
   run "${_lexer}" 1>&3

   echo "$output" 1>&3

#   assert_output 'declare -a FILE_LINES=()
#declare -- LEX_SUCCESS="yes"
#declare -a TOKENS=([0]="TOKEN_0")
#declare -A TOKEN_0=([file]="-1" [type]="EOF" [lineno]="" [colno]="" [offset]="" [value]="" )'
}

@test "lexer correctly identifies integers" { skip; }
