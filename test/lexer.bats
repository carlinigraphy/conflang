#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'
   source "${BATS_TEST_DIRNAME}"/../lib/errors.sh

   export lib_lexer="${BATS_TEST_DIRNAME}"/../lib/lexer.sh
}


@test "successful source" {
   source "$lib_lexer"
}


@test "fails with no input" {
   source "$lib_lexer"

   run init_scanner

   assert [ "$status" -eq "${EXIT_STATUS[no_input]}" ]
   assert_output 'File Error: missing input file.'
}


@test "runs with empty file" {
   : 'Given an empty input file, should successfully lex, generating only the
      final EOF token when closing the file.'

   declare -a FILES=( "${BATS_TEST_DIRNAME}"/share/empty.conf )
   source "$lib_lexer"

   init_scanner
   scan

   # Should have only an EOF token.
   assert [ ${#TOKENS[@]} -eq 1 ]

   local -n t="${TOKENS[0]}" 
   assert_equal "${t[type]}"  'EOF'
}


@test "identify valid symbols" {
   declare -a FILES=( "${BATS_TEST_DIRNAME}"/share/symbols.conf )
   source "$lib_lexer"

   init_scanner
   scan

   declare -A EXP_0=(  [type]="COLON"     [value]=":" )
   declare -A EXP_1=(  [type]="SEMI"      [value]=";" )
   declare -A EXP_2=(  [type]="MINUS"     [value]="-" )
   declare -A EXP_3=(  [type]="PERCENT"   [value]="%" )
   declare -A EXP_4=(  [type]="QUESTION"  [value]="?" )
   declare -A EXP_5=(  [type]="L_PAREN"   [value]="(" )
   declare -A EXP_6=(  [type]="R_PAREN"   [value]=")" )
   declare -A EXP_7=(  [type]="L_BRACKET" [value]="[" )
   declare -A EXP_8=(  [type]="R_BRACKET" [value]="]" )
   declare -A EXP_9=(  [type]="L_BRACE"   [value]="{" )
   declare -A EXP_10=( [type]="R_BRACE"   [value]="}" )
   declare -A EXP_11=( [type]="EOF"       [value]=""  )

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
   declare -a FILES=( "${BATS_TEST_DIRNAME}"/share/literals.conf )
   source "$lib_lexer"

   init_scanner
   scan

   # Keywords.
   declare -A EXP_0=(  [type]="INCLUDE"   [value]="include"     )
   declare -A EXP_1=(  [type]="CONSTRAIN" [value]="constrain"   )
   declare -A EXP_2=(  [type]="TRUE"      [value]="true"        )
   declare -A EXP_3=(  [type]="FALSE"     [value]="false"       )

   # Integers.
   declare -A EXP_4=(  [type]="INTEGER"    [value]="1"          )
   declare -A EXP_5=(  [type]="INTEGER"    [value]="100"        )
   declare -A EXP_6=(  [type]="INTEGER"    [value]="1234567890" )

   # Literals.
   declare -A EXP_7=(  [type]="IDENTIFIER" [value]="ident"      )
   declare -A EXP_8=(  [type]="STRING"     [value]="string"     )
   declare -A EXP_9=(  [type]="PATH"       [value]="path"       )

   # EOF.
   declare -A EXP_10=( [type]="EOF"        [value]=""           )


   for idx in "${!TOKENS[@]}" ; do
      local -- tname="${TOKENS[$idx]}"
      local -n token="$tname"

      local -- expected="EXP_${idx}"
      local -n etoken="$expected"

      assert_equal "${token[type]}"   "${etoken[type]}"
      assert_equal "${token[value]}"  "${etoken[value]}"
   done
}


@test "identify invalid tokens" {
   : 'While not testing every invalid token, a selection of invalid characters
      should all produce an `ERROR` token, with their value preserved.'

   declare -a FILES=( "${BATS_TEST_DIRNAME}"/share/invalid.conf )
   source "$lib_lexer"

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


@test "function declarations all have \`l_\` prefix" {
   : 'The lib/lexer.sh and lib/parser.sh files have many common functions and
      variables, whose names could stomp eachothers. For example: advance(), match(), $CURRENT, $PEEK.
      To avoid name stomping, lexer functions are prefixed by `l_`. Ensure that
      for every intended function, it contains the `l_` prefix.'

   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=(
      # Lexer functions intentionally without a prefix.
      [Token]='yes'
      [init_scanner]='yes'
      [scan]='yes'
   )

   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the lexer, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the lexer.
   source "$lib_lexer"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a missing_prefix=()
   for f in "${fns[@]}" ; do
      if [[ ! "$f" =~ ^l_ ]] && [[ ! "${filter[$f]}" ]] ; then
         missing_prefix+=( "$f" )
      fi
   done

   assert_equal "${#missing_prefix[@]}"  0
}


@test "function calls have intended \`l_\` prefix" {
   : "Can be easy to forget to add the l_ prefix when calling simple functions
      like advance() or munch(). Awk the full text to check."

   # Awk regex pattern for identifying function names in the `declare -f`
   # output.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=(
      # Lexer functions intentionally without a prefix.
      [Token]='yes'
      [init_scanner]='yes'
      [scan]='yes'
   )
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the lexer, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the lexer.
   source "$lib_lexer"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a lexer_fns=()
   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
         lexer_fns+=( "$f" )
      fi
   done

   _pattern=''
   for f in "${lexer_fns[@]}" ; do
      _pattern+="${_pattern:+|}${f#l_}"
   done
   pattern="($_pattern)"

   while read -r line ; do
      # Skip declarations. Sometimes there's crossover between a function name
      # (such as `l_number`) and a local variable (`number`).
      [[ "$line" =~ ^(local|declare) ]] && continue

      # Contains the name of a lexer function, minus the `l_` prefix. Could
      # potentially be a variable. Quick and dirty test if it's a function:
      if [[ "$line" =~ $pattern ]] ; then
         match="${BASH_REMATCH[0]}"

         # Mustn't have prefix,
         # be a variable,
         # or have any suffix
         if [[ ! "$line"  =~  (^|[[:space:]]+)l_${match} ]] && \
            [[ ! "$line"  =~  \$${match}                 ]] && \
            [[   "$line"  =~  ${match}(\$|\;)            ]]
         then
            printf '%3s%s\n' '' "$line" 1>&3
            return 1
         fi
      fi
   done< <( declare -f "${lexer_fns[@]}" )
}
