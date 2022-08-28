#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   source "${LIBDIR}/lexer.sh"
   source "${LIBDIR}/errors.sh"
}


@test "identify invalid tokens" {
   : 'While not testing every invalid token, a selection of invalid characters
      should all produce an `ERROR` token, with their value preserved.'

   declare -a FILES=( "${BATS_TEST_DIRNAME}"/data/invalid.conf )

   init_scanner
   scan

   declare -A EXP_0=( [type]="ERROR"  [value]="&" )
   declare -A EXP_1=( [type]="ERROR"  [value]="^" )
   declare -A EXP_2=( [type]="ERROR"  [value]="*" )
   declare -A EXP_3=( [type]="EOF"    [value]=""  )

   for idx in "${!TOKENS[@]}" ; do
      local -- tname="${TOKENS[$idx]}"
      local -n token="$tname"

      local -- expected="EXP_${idx}"
      local -n etoken="$expected"

      assert_equal "${token[type]}"   "${etoken[type]}"
      assert_equal "${token[value]}"  "${etoken[value]}"
   done
}


@test "identify valid symbols" {
   declare -a FILES=( "${BATS_TEST_DIRNAME}"/data/symbols.conf )

   init_scanner
   scan

   declare -A EXP_0=(  [type]="DOT"        [value]="."  )
   declare -A EXP_1=(  [type]="COMMA"      [value]=","  )
   declare -A EXP_2=(  [type]="SEMI"       [value]=";"  )
   declare -A EXP_3=(  [type]="COLON"      [value]=":"  )
   declare -A EXP_4=(  [type]="DOLLAR"     [value]="$"  )
   declare -A EXP_5=(  [type]="PERCENT"    [value]="%"  )
   declare -A EXP_6=(  [type]="QUESTION"   [value]="?"  )
   declare -A EXP_7=(  [type]="MINUS"      [value]="-"  )
   declare -A EXP_8=(  [type]="ARROW"      [value]="->" )
   declare -A EXP_9=(  [type]="L_PAREN"    [value]="("  )
   declare -A EXP_10=( [type]="R_PAREN"    [value]=")"  )
   declare -A EXP_11=( [type]="L_BRACKET"  [value]="["  )
   declare -A EXP_12=( [type]="R_BRACKET"  [value]="]"  )
   declare -A EXP_13=( [type]="L_BRACE"    [value]="{"  )
   declare -A EXP_14=( [type]="R_BRACE"    [value]="}"  )
   declare -A EXP_15=( [type]="EOF"        [value]=""   )

   for idx in "${!TOKENS[@]}" ; do
      local -- tname="${TOKENS[$idx]}"
      local -n token="$tname"

      local -- expected="EXP_$idx"
      local -n etoken="$expected"

      assert_equal "${token[type]}"   "${etoken[type]}"
      assert_equal "${token[value]}"  "${etoken[value]}"
   done
}


@test "identify valid literals" {
   declare -a FILES=( "${BATS_TEST_DIRNAME}"/data/literals.conf )

   init_scanner
   scan

   # Keywords.
   declare -A EXP_0=(  [type]="INCLUDE"     [value]="include"    )
   declare -A EXP_1=(  [type]="CONSTRAIN"   [value]="constrain"  )
   declare -A EXP_2=(  [type]="TRUE"        [value]="true"       )
   declare -A EXP_3=(  [type]="FALSE"       [value]="false"      )

   # Integers.
   declare -A EXP_4=(  [type]="INTEGER"     [value]="1"          )
   declare -A EXP_5=(  [type]="INTEGER"     [value]="100"        )
   declare -A EXP_6=(  [type]="INTEGER"     [value]="1234567890" )

   # Literals.
   declare -A EXP_7=(  [type]="IDENTIFIER"  [value]="ident"      )
   declare -A EXP_8=(  [type]="STRING"      [value]="string"     )
   declare -A EXP_9=(  [type]="PATH"        [value]="path"       )

   # Escaped quotes in string, path
   declare -A EXP_10=( [type]="STRING"      [value]='"'          )
   declare -A EXP_11=( [type]="PATH"        [value]="'"          )

   # EOF.
   declare -A EXP_12=( [type]="EOF"         [value]=""           )

      
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
   declare -a FILES=(
      "${BATS_TEST_DIRNAME}/data/interpolation/basic.conf"
   )

   init_scanner
   run scan

   # fpath.
   declare -A EXP_0=(  [type]='PATH'        [value]='an fpath: '   )
   declare -A EXP_1=(  [type]='CONCAT'      [value]=''             )
   declare -A EXP_2=(  [type]='DOLLAR'      [value]='$'            )
   declare -A EXP_3=(  [type]='IDENTIFIER'  [value]='HERE'         )
   declare -A EXP_4=(  [type]='CONCAT'      [value]=''             )
   declare -A EXP_5=(  [type]='PATH'        [value]='.'            )

   # fstring.
   declare -A EXP_6=(  [type]='STRING'      [value]='an fstring: ' )
   declare -A EXP_7=(  [type]='CONCAT'      [value]=''             )
   declare -A EXP_8=(  [type]='DOLLAR'      [value]='$'            )
   declare -A EXP_9=(  [type]='IDENTIFIER'  [value]='HERE'         )
   declare -A EXP_10=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_11=( [type]='STRING'      [value]='.'            )

   # fstring.
   declare -A EXP_12=( [type]='STRING'      [value]=''             )
   declare -A EXP_13=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_14=( [type]='PERCENT'     [value]='%'            )
   declare -A EXP_15=( [type]='IDENTIFIER'  [value]='internal'     )
   declare -A EXP_16=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_17=( [type]='STRING'      [value]=''             )

   # fpath.
   declare -A EXP_18=( [type]='PATH'        [value]=''             )
   declare -A EXP_19=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_20=( [type]='PERCENT'     [value]='%'            )
   declare -A EXP_21=( [type]='IDENTIFIER'  [value]='internal'     )
   declare -A EXP_22=( [type]='CONCAT'      [value]=''             )
   declare -A EXP_23=( [type]='PATH'        [value]=''             )

   # escaped braces
   declare -A EXP_24=( [type]='PATH'        [value]="{ ' }"        )
   declare -A EXP_25=( [type]='STRING'      [value]='{ " }'        )

   # EOF.
   declare -A EXP_12=( [type]='EOF'         [value]=''             )


   for idx in "${!TOKENS[@]}" ; do
      local -- tname="${TOKENS[$idx]}"
      local -n token="$tname"

      local -- expected="EXP_${idx}"
      local -n etoken="$expected"

      assert_equal "${token[type]}"   "${etoken[type]}"
      assert_equal "${token[value]}"  "${etoken[value]}"
   done
}
