#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local SRC="${BATS_TEST_DIRNAME}/../../src"
   export _LEXER_SH="${SRC}/lexer.sh"
}


@test "function declarations all have \`lexer:\` prefix" {
   : 'The lib/lexer.sh and lib/parser.sh files have many common functions and
      variables, whose names could stomp eachothers. For example: advance(),
      match(), $CURRENT, $PEEK.  To avoid name stomping, lexer functions are
      prefixed by `lexer:`. Ensure that for every intended function, it
      contains the `lexer:` prefix.'

   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   # Lexer functions intentionally without a prefix.
   local -A filter=(
      [Token]='yes'
   )

   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the lexer, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the lexer.
   source "$_LEXER_SH"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a missing_prefix=()
   for f in "${fns[@]}" ; do
      if [[ ! "$f" =~ ^lexer: ]] && [[ ! "${filter[$f]}" ]] ; then
         missing_prefix+=( "$f" )
      fi
   done

   assert_equal "${#missing_prefix[@]}"  0
}


@test "function calls have intended \`lexer:\` prefix" {
   # Awk regex pattern for identifying function names in the `declare -f`
   # output.
   pattern='/^[[:alpha:]_][[:alnum:]_:]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   # Lexer functions intentionally without a prefix.
   local -A filter=(
      [Token]='yes'
   )
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the lexer, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the lexer.
   source "$_LEXER_SH"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a lexer_fns=()
   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
         lexer_fns+=( "$f" )
      fi
   done

   pattern=''
   for f in "${lexer_fns[@]}" ; do
      pattern+="${pattern:+|}${f#lexer:}"
   done
   pattern="(${pattern})"

   while read -r line ; do
      # Skip declarations. Sometimes there's crossover between a function name
      # (such as `lexer:number`) and a local variable (`number`).
      [[ "$line" =~ ^(local|declare) ]] && continue

      # Contains the name of a lexer function, minus the `lexer:` prefix. Could
      # potentially be a variable. Quick and dirty test if it's a function:
      if [[ "$line" =~ $pattern ]] ; then
         match="${BASH_REMATCH[0]}"

         # Mustn't have prefix, be a variable, or have any suffix.
         if [[ ! "$line"  =~  (^|[[:space:]]+)lexer:${match} ]] && \
            [[ ! "$line"  =~  \$${match}                     ]] && \
            [[   "$line"  =~  ${match}(\$|\;)                ]]
         then
            printf '%3s%s\n' '' "$line" 1>&3
            return 1
         fi
      fi
   done< <( declare -f "${lexer_fns[@]}" )
}
