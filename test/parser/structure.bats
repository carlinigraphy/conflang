#!/usr/bin/bats
# vim:ft=sh

function setup {
   load '/usr/lib/bats-assert/load.bash'
   load '/usr/lib/bats-support/load.bash'

   local src="${BATS_TEST_DIRNAME}/../../src"
   export _LEXER_SH="${src}/lexer.sh"
   export _PARSER_SH="${src}/parser.sh"
}


@test "function declarations all have \`parser:\` prefix" {
   : 'The lib/lexer.sh and lib/parser.sh files have many common functions and
      variables, whose names could stomp eachothers. For example: advance(),
      match(), $CURRENT, $PEEK.  To avoid name stomping, parser functions are
      prefixed by `parser:`. Ensure that for every intended function, it
      contains the `parser:` prefix.'

   # Awk regex pattern.
   pattern='/^[[:alpha:]_][[:alnum:]_:]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the parser function names. Filter them out.
   readarray -td $'\n' _fns < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=(
      [ast:new]='yes' 
      [_ast_new_program]='yes'
      [_ast_new_header]='yes'
      [_ast_new_import]='yes'
      [_ast_new_typedef]='yes'
      [_ast_new_container]='yes'
      [_ast_new_decl_section]='yes'
      [_ast_new_decl_variable]='yes'
      [_ast_new_list]='yes'
      [_ast_new_record]='yes'
      [_ast_new_type]='yes'
      [_ast_new_typecast]='yes'
      [_ast_new_member]='yes'
      [_ast_new_index]='yes'
      [_ast_new_unary]='yes'
      [_ast_new_boolean]='yes'
      [_ast_new_integer]='yes'
      [_ast_new_string]='yes'
      [_ast_new_path]='yes' 
      [_ast_new_identifier]='yes' 
      [_ast_new_env_var]='yes' 
   )

   for f in "${_fns[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the parser, compile list of function names. Iterating this, and
   # filtering out anything defined previously, should give us only those
   # created within the parse.
   source "$_PARSER_SH"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a missing_prefix=()
   for f in "${fns[@]}" ; do
      if [[ ! "$f" =~ ^parser: ]] && [[ ! "${filter[$f]}" ]] ; then
         missing_prefix+=( "$f" )
      fi
   done

   assert_equal "${missing_prefix[@]}"  ''
}


@test "function calls have intended \`parser:\` prefix" {
   : "Can be easy to forget to add the parser: prefix when calling simple
      functions like advance() or munch(). Awk the full text to check"

   # Awk regex pattern for identifying function names in the `declare -f`
   # output.
   pattern='/^[[:alpha:]_][[:alnum:]_:]* \(\)/'

   # Get initial list of functions from the environment. Don't want these
   # polluting the results from the lexer function names. Filter them out.
   readarray -td $'\n' _filter < <(declare -f | awk "${pattern} {print \$1}")

   local -A filter=()
   for f in "${_filter[@]}" ; do
      filter["$f"]='yes'
   done

   # Source in the parser, compile list of function names. Iterating this,
   # and filtering out anything defined previously, should give us only those
   # created within the parser.
   source "$_PARSER_SH"
   readarray -td $'\n' fns < <(declare -f | awk "${pattern} {print \$1}")

   local -a parser_fns=()
   for f in "${fns[@]}" ; do
      if [[ ! "${filter[$f]}" ]] ; then
         parser_fns+=( "$f" )
      fi
   done

   _pattern=''
   for f in "${parser_fns[@]}" ; do
      _pattern+="${_pattern:+|}${f#parser:}"
   done
   pattern="($_pattern)"

   while read -r line ; do
      # Skip declarations. Sometimes there's crossover between a function name
      # (such as `parser:number`) and a local variable (`number`).
      [[ "$line" =~ ^(local|declare) ]] && continue

      # Contains the name of a parser function, minus the `parser:` prefix.
      # Could potentially be a variable. Quick and dirty test if it's a
      # function:
      if [[ "$line" =~ $pattern ]] ; then
         match="${BASH_REMATCH[0]}"

         # Mustn't have prefix,
         # be a `class` mk_* function,
         # be a variable,
         # or have any suffix
         if [[ ! "$line"  =~  (^|[[:space:]]+)parser:${match} ]] && \
            [[ ! "$line"  =~  \$${match}                      ]] && \
            [[ ! "$line"  =~  mk_${match}                     ]] && \
            [[   "$line"  =~  ${match}(\$|\;)                 ]]
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
   source "$_LEXER_SH"
   readarray -td $'\n' _lex_fns < <(declare -f | awk "${pattern} {print \$1}" | sort)
   readarray -td $'\n'  lex_fns < <(
         comm -13 \
         <(printf '%s\n' "${filter[@]}") \
         <(printf '%s\n' "${_lex_fns[@]}")
   )
   unset "${lex_fns[@]}" 

   # Only parser functions.
   source "$_PARSER_SH"
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
