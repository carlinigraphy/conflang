#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local SRC="${BATS_TEST_DIRNAME}/../../src"
   source "${SRC}/main"
   source "${SRC}/files.sh"
   source "${SRC}/lexer.sh"
   source "${SRC}/parser.sh"
   source "${SRC}/errors.sh"

   export F=$( mktemp "${BATS_TEST_TMPDIR}"/XXX ) 
   globals:init

   file:new
   file:resolve "$F"
}


@test "identify invalid tokens" {
   : 'While not testing every invalid token, a selection of invalid characters
      should all produce an `ERROR` token, with their value preserved.'

   for char in '%'  '^'  '*' ; do
      echo "$char" > "$F"
      lexer:init
      run lexer:scan

      assert_failure
      assert_equal  "$status"  ${ERROR_CODE['syntax_error']%%,*} 
   done
}


@test "identify valid symbols" {
   echo  '., ;: $ ? -> - () [] {} #Comment' > "$F"
   lexer:init ; lexer:scan

   declare -A EXP_0=(  [type]="DOT"        [value]="."  )
   declare -A EXP_1=(  [type]="COMMA"      [value]=","  )
   declare -A EXP_2=(  [type]="SEMI"       [value]=";"  )
   declare -A EXP_3=(  [type]="COLON"      [value]=":"  )
   declare -A EXP_4=(  [type]="DOLLAR"     [value]="$"  )
   declare -A EXP_5=(  [type]="QUESTION"   [value]="?"  )
   declare -A EXP_6=(  [type]="ARROW"      [value]="->" )
   declare -A EXP_7=(  [type]="MINUS"      [value]="-"  )
   declare -A EXP_8=(  [type]="L_PAREN"    [value]="("  )
   declare -A EXP_9=(  [type]="R_PAREN"    [value]=")"  )
   declare -A EXP_10=( [type]="L_BRACKET"  [value]="["  )
   declare -A EXP_11=( [type]="R_BRACKET"  [value]="]"  )
   declare -A EXP_12=( [type]="L_BRACE"    [value]="{"  )
   declare -A EXP_13=( [type]="R_BRACE"    [value]="}"  )
   declare -A EXP_14=( [type]="EOF"        [value]=""   )

   assert [ ${#TOKENS[@]} -gt 0 ]

   for idx in "${!TOKENS[@]}" ; do
      local -- token="${TOKENS[$idx]}"
      local -n token_r="$token"

      local -- expected="EXP_$idx"
      local -n expected_r="$expected"

      assert_equal "${token_r[type]}"   "${expected_r[type]}"
      assert_equal "${token_r[value]}"  "${expected_r[value]}"
   done
}


@test "identify valid literals" {
   cat << EOF > "$F"
      # Keywords.
      import
      as
      typedef
      true
      false

      # Integers.
      1
      100
      1234567890

      # Literals.
      ident
      "string"
      'path'

      "\""  # String with escaped: "
      '\''  # Path with escaped: '
EOF

   lexer:init
   lexer:scan

   # Keywords.
   declare -A EXP_0=(  [type]="IMPORT"      [value]="import"     )
   declare -A EXP_1=(  [type]="AS"          [value]="as"         )
   declare -A EXP_2=(  [type]="TYPEDEF"     [value]="typedef"    )
   declare -A EXP_3=(  [type]="TRUE"        [value]="true"       )
   declare -A EXP_4=(  [type]="FALSE"       [value]="false"      )

   # Integers.
   declare -A EXP_5=(  [type]="INTEGER"     [value]="1"          )
   declare -A EXP_6=(  [type]="INTEGER"     [value]="100"        )
   declare -A EXP_7=(  [type]="INTEGER"     [value]="1234567890" )

   # Literals.
   declare -A EXP_8=(  [type]="IDENTIFIER"  [value]="ident"      )
   declare -A EXP_9=(  [type]="STRING"      [value]="string"     )
   declare -A EXP_10=( [type]="PATH"        [value]="path"       )

   # Escaped quotes in string, path
   declare -A EXP_11=( [type]="STRING"      [value]='"'          )
   declare -A EXP_12=( [type]="PATH"        [value]="'"          )

   # EOF.
   declare -A EXP_13=( [type]="EOF"         [value]=""           )

      
   assert [ ${#TOKENS[@]} -gt 0 ]

   for idx in "${!TOKENS[@]}" ; do
      local -- tname="${TOKENS[$idx]}"
      local -n token="$tname"

      local -- expected="EXP_${idx}"
      local -n etoken="$expected"

      assert_equal "${token[type]}"   "${etoken[type]}"
      assert_equal "${token[value]}"  "${etoken[value]}"
   done
}


@test "identify fstring, fpath" {
   cat << EOF > "$F"
      f'before{\$HERE}after'
      f"before{\$HERE}after"

      f'{ internal }'
      f"{ internal }"

      f'\{ \' \}'
      f"\{ \" \}"
EOF

   lexer:init
   lexer:scan 

   # fpath.
   declare -A EXP_0=(  [type]='PATH'        [value]='before'       )
   declare -A EXP_1=(  [type]='CONCAT'      [value]=''             )
   declare -A EXP_2=(  [type]='DOLLAR'      [value]='$'            )
   declare -A EXP_3=(  [type]='IDENTIFIER'  [value]='HERE'         )
   declare -A EXP_4=(  [type]='CONCAT'      [value]=''             )
   declare -A EXP_5=(  [type]='PATH'        [value]='after'        )

   # fstring.
   declare -A EXP_6=(  [type]='STRING'      [value]='before'       )
   declare -A EXP_7=(  [type]='CONCAT'      [value]=''             )
   declare -A EXP_8=(  [type]='DOLLAR'      [value]='$'            )
   declare -A EXP_9=(  [type]='IDENTIFIER'  [value]='HERE'         )
   declare -A EXP_10=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_11=( [type]='STRING'      [value]='after'        )

   # fpath.
   declare -A EXP_12=( [type]='PATH'        [value]=''             )
   declare -A EXP_13=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_14=( [type]='IDENTIFIER'  [value]='internal'     )
   declare -A EXP_15=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_16=( [type]='PATH'        [value]=''             )

   # fstring.
   declare -A EXP_17=( [type]='STRING'      [value]=''             )
   declare -A EXP_18=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_19=( [type]='IDENTIFIER'  [value]='internal'     )
   declare -A EXP_20=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_21=( [type]='STRING'      [value]=''             )

   # escaped braces
   declare -A EXP_22=( [type]='PATH'        [value]="{ ' }"        )
   declare -A EXP_23=( [type]='STRING'      [value]='{ " }'        )

   # EOF.
   declare -A EXP_24=( [type]='EOF'         [value]=''             )

   assert [ ${#TOKENS[@]} -gt 0 ]

   for idx in "${!TOKENS[@]}" ; do
      local -- tname="${TOKENS[$idx]}"
      local -n token="$tname"

      local -- expected="EXP_${idx}"
      local -n etoken="$expected"

      assert_equal "${token[type]}"   "${etoken[type]}"
      assert_equal "${token[value]}"  "${etoken[value]}"
   done
}
