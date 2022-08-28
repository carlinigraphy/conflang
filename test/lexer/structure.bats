#!/usr/bin/env bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   export LIBDIR="${BATS_TEST_DIRNAME}/../../lib"
   export lib_lexer="${LIBDIR}/lexer.sh"
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
