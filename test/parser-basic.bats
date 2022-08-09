#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'
   source "${BATS_TEST_DIRNAME}"/../lib/errors.sh

   export lib_lexer="${BATS_TEST_DIRNAME}"/../lib/lexer.sh
   export lib_parser="${BATS_TEST_DIRNAME}"/../lib/parser.sh
}


@test "successful source" {
   source "$lib_parser"
}


@test "fails with no tokens" {
   source "$lib_parser"
   run parse
   assert_failure
}


@test "runs with only EOF token" {
   : 'While the parser should fail given *NO* tokens in the input, it should
      successfully parse an empty file (only EOF token).'

   source "${BATS_TEST_DIRNAME}"/parser/empty.tokens
   source "$lib_parser"
   parse
}


@test "lexer -> parser with empty file" {
   : 'More complete test, starting from the lexer, transitioning into the
      parser. Testing handoff.'

   source "$lib_lexer"
   source "$lib_parser"

   declare -a FILES=( "${BATS_TEST_DIRNAME}"/share/empty.conf )

   init_scanner
   scan
   parse
}


@test "lexer -> parser with simple data" {
   : 'Must check the lexer successfully hands off everything to the parser.
      and no additional global vars/functions are unspecified'

   source "$lib_lexer"
   source "$lib_parser"

   declare -a FILES=( "${BATS_TEST_DIRNAME}"/parser/simple.conf )

   init_scanner
   scan
   run parse

   assert_success
}


@test "function declarations all have \`p_\` prefix" {
   : 'The lib/lexer.sh and lib/parser.sh files have many common functions and
      variables, whose names could stomp eachothers. For example: advance(), match(), $CURRENT, $PEEK.
      To avoid name stomping, parser functions are prefixed by `p_`. Ensure that
      for every intended function, it contains the `p_` prefix.'

   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the parser function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=(
      [mk_array]='yes'
      [mk_boolean]='yes'
      [mk_context_block]='yes'
      [mk_context_directive]='yes'
      [mk_context_test]='yes'
      [mk_decl_section]='yes'
      [mk_decl_variable]='yes'
      [mk_func_call]='yes'
      [mk_variable]='yes'
      [mk_identifier]='yes'
      [mk_include]='yes'
      [mk_integer]='yes'
      [mk_path]='yes'
      [mk_string]='yes'
      [mk_typedef]='yes'
      [mk_unary]='yes'
      [parse]='yes'
   )

   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the parser, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the parse.
   source "$lib_parser"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a missing_prefix=()
   for f in "${fns[@]}" ; do
      if [[ ! "$f" =~ ^p_ ]] && [[ ! "${filter[$f]}" ]] ; then
         missing_prefix+=( "$f" )
      fi
   done

   assert_equal "${#missing_prefix[@]}"  0
}


@test "function calls have intended \`p_\` prefix" {
   : "Can be easy to forget to add the p_ prefix when calling simple functions
      like advance() or munch(). Awk the full text to check"

   # Awk regex pattern for identifying function names in the `declare -f`
   # output.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=(
      # Parser functions intentionally without a prefix.
      [mk_array]='yes'
      [mk_boolean]='yes'
      [mk_context_block]='yes'
      [mk_context_directive]='yes'
      [mk_context_test]='yes'
      [mk_decl_section]='yes'
      [mk_decl_variable]='yes'
      [mk_func_call]='yes'
      [mk_variable]='yes'
      [mk_identifier]='yes'
      [mk_include]='yes'
      [mk_integer]='yes'
      [mk_path]='yes'
      [mk_string]='yes'
      [mk_typedef]='yes'
      [mk_unary]='yes'
      [parse]='yes'
   )
   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the parser, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the parser.
   source "$lib_parser"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a parser_fns=()
   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
         parser_fns+=( "$f" )
      fi
   done

   _pattern=''
   for f in "${parser_fns[@]}" ; do
      _pattern+="${_pattern:+|}${f#p_}"
   done
   pattern="($_pattern)"

   while read -r line ; do
      # Skip declarations. Sometimes there's crossover between a function name
      # (such as `p_number`) and a local variable (`number`).
      [[ "$line" =~ ^(local|declare) ]] && continue

      # Contains the name of a parser function, minus the `p_` prefix. Could
      # potentially be a variable. Quick and dirty test if it's a function:
      if [[ "$line" =~ $pattern ]] ; then
         match="${BASH_REMATCH[0]}"

         # Mustn't have prefix,
         # be a `class` mk_* function,
         # be a variable,
         # or have any suffix
         if [[ ! "$line"  =~  (^|[[:space:]]+)p_${match} ]] && \
            [[ ! "$line"  =~  \$${match}                 ]] && \
            [[ ! "$line"  =~  mk_${match}                ]] && \
            [[   "$line"  =~  ${match}(\$|\;)            ]]
         then
            printf '%3s%s\n' '' "$line  --->  matched(${match})" 1>&3
            return 1
         fi
      fi
   done< <( declare -f "${parser_fns[@]}" )
}


@test "No function overlap between lexer and parser" {
   # Awk regex pattern for identifying function names in the `declare -f`
   # output.
   pattern='/^[[:alpha:]_][[:alnum:]_]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' filter < <(declare -f | awk "${pattern} {print \$1}" | sort)

   # Only lexer functions.
   source "$lib_lexer"
   readarray -td $'\n' _lex_fns < <(declare -f | awk "${pattern} {print \$1}" | sort)
   readarray -td $'\n'  lex_fns < <(
         comm -13 \
         <(printf '%s\n' "${filter[@]}") \
         <(printf '%s\n' "${_lex_fns[@]}")
   )
   unset "${lex_fns[@]}" 

   # Only parser functions.
   source "$lib_parser"
   readarray -td $'\n' _parse_fns < <(declare -f | awk "${pattern} {print \$1}" | sort)
   readarray -td $'\n'  parse_fns < <(
         comm -13 \
         <(printf '%s\n' "${filter[@]}") \
         <(printf '%s\n' "${_parse_fns[@]}")
   )
   unset "${parse_fns[@]}" 

   # Intersection of lexer & parser. Ideally 0.
   readarray -td $'\n' intersection < <(
         comm -13
         <(printf '%s\n' "${lex_fns[@]}") \
         <(printf '%s\n' "${parse_fns[@]}")
   )

   assert_equal "${#intersection[@]}"  0
}
