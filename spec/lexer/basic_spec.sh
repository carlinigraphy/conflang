Describe 'lexer'
   source lib/lexer.sh
   FILES=( /dev/stdin )

   It 'identifies invalid symbols'
      init_scanner

      Data
         #| & ^ *
      End

      When call scan
      declare -A EXP_0=( [type]="ERROR"  [value]="&" )
      declare -A EXP_1=( [type]="ERROR"  [value]="^" )
      declare -A EXP_2=( [type]="ERROR"  [value]="*" )
      declare -A EXP_3=( [type]="EOF"    [value]=""  )

      # There must actually be tokens generated. If we only iterate the array of
      # TOKENS (assumingly populated and included from the scanner), we run the
      # risk of iterating a 0-member array.
      The value ${#TOKENS[@]} should not equal 0

      for idx in "${!TOKENS[@]}" ; do
         local -- tname="${TOKENS[$idx]}"
         local -n token="$tname"

         local -- expected="EXP_${idx}"
         local -n etoken="$expected"

         The value ${token[type]}  should equal "${etoken[type]}"
         The value ${token[value]} should equal "${etoken[value]}"
      done
   End
End
