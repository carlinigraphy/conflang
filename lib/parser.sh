#!/bin/bash
#
# Requires from ENV:
#  TOKENS[]             # Array of token names
#  TOKEN_$n             # Sequence of all token objects
#  FILES[]              # Array of imported files
# }

#═════════════════════════════════╡ AST NODES ╞═════════════════════════════════
declare -gi  NODE_NUM=0
declare -gi  INCLUDE_NUM=0

# `include` & `constrain` directives are handled by the parser. They don't
# create NODES_$n's.
declare -ga  INCLUDES=() CONSTRAINTS=()
# Both hold lists.
# Sub-objects:
#> INCLUDES=([0]='INCLUDE_1', [1]='INCLUDE_2')
#> INCLUDE_1=([path]='./colors.conf' [target]='NODE_01')
#> INCLUDE_1=([path]='./keybinds.conf' [target]='NODE_25')
#>
# Raw values:
#> CONSTRAINTS=('./subfile1.conf', './subfile2.conf')

# Saves us from a get_type() function call, or some equivalent.
declare -gA  TYPEOF=()


function mk_decl_section {
   # 1) create parent
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Set global SECTION pointer here for validating %constrain blocks, and
   # setting $target of %include's
   declare -g SECTION=$nname

   # 2) create list to hold the items within the section.
   (( ++NODE_NUM ))
   local nname_items="NODE_${NODE_NUM}"
   declare -ga $nname_items

   # 3) assign child node to parent.
   node['name']=
   node['items']=$nname_items

   # 4) Meta information, for easier parsing.
   TYPEOF[$nname]='decl_section'
}


function mk_include {
   (( ++INCLUDE_NUM ))
   local   --  iname="INCLUDE_${INCLUDE_NUM}"
   declare -gA $iname
   declare -g  INCLUDE=$iname
   local   -n  include=$iname

   include['path']=
   include['target']=

   INCLUDES+=( "$iname" )
}


function mk_decl_variable {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['name']=       # identifier
   node['type']=       # type
   node['expr']=       # section, array, int, str, bool, path

   TYPEOF[$nname]='decl_variable'
}


function mk_array {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -ga $nname
   declare -g  NODE=$nname

   TYPEOF[$nname]='array'
}


function mk_typedef {
   (( ++NODE_NUM ))
   local nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node['kind']=          # Primitive type
   node['subtype']=       # Sub `Type' node

   TYPEOF[$nname]='typedef'
}


function mk_typecast {
   (( ++NODE_NUM ))
   local nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node['expr']=
   node['typedef']=

   TYPEOF[$nname]='typecast'
}


function mk_index {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['left']=
   node['right']=

   TYPEOF[$nname]='index'
}


function mk_unary {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['op']=
   node['right']=

   TYPEOF[$nname]='unary'
}


function mk_boolean {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   TYPEOF[$nname]='boolean'
}


function mk_integer {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   TYPEOF[$nname]='integer'
}


function mk_string {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   TYPEOF[$nname]='string'
}


function mk_path {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   TYPEOF[$nname]='path'
}


function mk_identifier {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   # shellcheck disable=SC2034
   TYPEOF[$nname]='identifier'
}


function mk_env_var {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   # shellcheck disable=SC2034
   TYPEOF[$nname]='env_var'
}


function mk_int_var {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node['value']=
   node['offset']=
   node['lineno']=
   node['colno']=
   node['file']=

   # shellcheck disable=SC2034
   TYPEOF[$nname]='int_var'
}


#═══════════════════════════════════╡ utils ╞═══════════════════════════════════
function init_parser {
   declare -gi IDX=0
   declare -g  CURRENT=''  CURRENT_NAME=''
   # Calls to `advance' both globally set the name of the current/next node(s),
   # e.g., `TOKEN_1', as well as declaring a nameref to the variable itself.

   # Should be reset on every run, as it's unique to this instance of the parser.
   declare -g  ROOT=''  # Solely used to indicate the root of the AST.
   declare -g  NODE=''
   declare -g  INCLUDE=''

   # Need to take note of the section.
   # `%include` blocks must reference the target Section to include any included
   # sub-nodes.
   # `%constrain` blocks must check they are not placed anywhere but a top-level
   # %inline section.
   declare -g SECTION=''
}


function p_advance {
   while [[ $IDX -lt ${#TOKENS[@]} ]] ; do
      declare -g  CURRENT_NAME=${TOKENS[$IDX]}
      declare -gn CURRENT=$CURRENT_NAME

      if [[ ${CURRENT[type]} == 'ERROR' ]] ; then
         raise syntax_error "$CURRENT_NAME"
      else
         break
      fi
   done

   (( ++IDX ))
}


function p_check {
   # Allows for passing in something like: "L_BRACKET,STRING,INTEGER" to check
   # multiple tokens.
   [[ ,"$1", ==  *,${CURRENT[type]},* ]]
}


function p_match {
   if p_check "$1" ; then
      p_advance
      return 0
   fi

   return 1
}


function p_munch {
   if ! p_check "$1" ; then
      raise munch_error  "$1"  "$CURRENT_NAME"  "$2"
   fi

   p_advance
}


function parse {
   # Realistically this should not happen, outside running the lexer & parser
   # independently. Though it's a prerequisite for all that follows.
   if [[ "${#TOKENS[0]}" -eq 0 ]] ; then
      raise parse_error "didn't receive tokens from lexer."
   fi

   p_advance
   p_program
}

#═════════════════════════════╡ GRAMMAR FUNCTIONS ╞═════════════════════════════
function p_program {
   # This is preeeeeeeeeeeeetty janky. I don't love it. Since this pseudo-
   # section doesn't actually exist in-code, it doesn't have any opening or
   # closing braces. So `section()` gets fucked up when trying to munch a
   # closing brace. Gotta just in-line stuff here all hacky-like.
   #
   # Creates a default top-level `section', allowing top-level key:value pairs,
   # wout requiring a dict (take that, JSON).
   mk_identifier

   local -- nname=$NODE
   local -n name=$nname
   name['value']='%inline'
   name['offset']=0
   name['lineno']=0
   name['colno']=0
   name['file']="${FILE_IDX}"

   mk_decl_section

   # shellcheck disable=SC2034
   declare -g ROOT=$NODE
   local   -n node=$NODE
   local   -n items=${node['items']}

   node['name']=$nname

   while ! p_check 'EOF' ; do
      p_statement

      # %include/%constrain are statements, but do not have an associated $NODE.
      # Need to avoid adding an empty string to the section.items[]
      if [[ $NODE ]] ; then
         items+=( "$NODE" )
      fi
   done

   p_munch 'EOF'
}


function p_statement {
   if p_match 'PERCENT' ; then
      p_parser_statement
   else
      p_declaration
   fi
}


function p_parser_statement {
   # Saved node referencing the parent Section.
   if p_match 'INCLUDE' ; then
      p_include
   elif p_match 'CONSTRAIN' ; then
      p_constrain
   else
      raise parse_error "${CURRENT[value]} is not a parser statement."
   fi

   p_munch 'SEMI' "expecting \`;' after parser statement."
}


function p_include {
   mk_include
   local -n include=$INCLUDE

   # When used outside the `p_expression()` function, need to explicitly pass
   # in a refernce to the current token.
   p_path "$CURRENT_NAME"
   p_munch 'PATH' "expecting path after %include."

   local -n path=$NODE
   # shellcheck disable=SC2034 
   include['path']=${path[value]}
   include['target']=$SECTION

   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they do
   # not live past the parser.
}


function p_constrain {
   local -n section_ptr=$SECTION
   local -n name=${section_ptr[name]}

   if [[ ${name[value]} != '%inline' ]] ; then
      raise parse_error '%constrain may not occur in a section.'
   fi

   if [[ ${name[file]} -ne 0 ]] ; then
      raise parse_error '%constrain may not occur in a sub-file.'
   fi

   if [[ "${#CONSTRAINTS[@]}" -gt 0 ]] ; then
      raise parse_error 'may not specify multiple constrain blocks.'
   fi

   # TODO: refactor
   # This should probably just call `p_array`. Then we can pull the paths out
   # from within it? Rearpb making it a special case. Or maybe just straight
   # up call `p_expression`. Hmm.
   p_munch 'L_BRACKET' "expecting \`[' to begin array of paths."
   while ! p_check 'R_BRACKET' ; do
      # When used outside the `p_expression()` function, need to explicitly
      # pass in a refernce to the current token.
      p_path "$CURRENT_NAME"
      p_munch 'PATH' 'expecting an array of paths.'

      local -n path=$NODE
      CONSTRAINTS+=( "${path[value]}" )
   done

   p_munch 'R_BRACKET' "expecting \`]' after constrain block."
   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they do
   # not live past the parser.
}


function p_declaration {
   p_identifier "$CURRENT_NAME"
   p_munch 'IDENTIFIER' "expecting variable declaration."

   if p_match 'L_BRACE' ; then
      p_decl_section
   else
      p_decl_variable
   fi
}


function p_decl_section {
   local -- name=$NODE
   local -- sect=$SECTION

   mk_decl_section
   local -- save=$NODE
   local -n node=$NODE
   local -n items=${node['items']}

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128 
   node['name']="$name"

   while ! p_check 'R_BRACE' ; do
      p_statement

      # %include/%constrain are statements, but do not have an associated $NODE.
      # Need to avoid adding an empty string to the section.items[]
      if [[ $NODE ]] ; then
         items+=( "$NODE" )
      fi
   done

   p_munch 'R_BRACE' "expecting \`}' after section."
   declare -g NODE="$save"
   declare -g SECTION="$sect"
}


function p_decl_variable {
   # Variable declaration must be preceded by an identifier.
   local -- name=$NODE

   mk_decl_variable
   local -- save=$NODE
   local -n node=$NODE

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128
   node['name']=$name

   # Typedefs.
   if p_match 'L_PAREN' ; then
      p_typedef
      p_munch 'R_PAREN' "typedef must be closed by \`)'."
      node['type']=$NODE
   fi

   # For better error reporting. If the user passes a token that begins an
   # expression (literally defined in the pratt parsing section as a null
   # denomination), throw error specifically indicating that they likely
   # intended to precede with a colon.
   local expr_str=''
   for expr in "${!NUD[@]}" ; do
      expr_str+="${expr_str:+,}${expr}"
   done

   # Expressions.
   if p_match 'COLON' ; then
      p_expression
      node['expr']=$NODE
   elif p_match "$expr_str" ; then
      raise parse_error "expecting \`:' before expression."
   fi

   p_munch 'SEMI' "expecting \`;' after declaration."
   declare -g NODE=$save
}


function p_typedef {
   p_identifier "$CURRENT_NAME"
   p_munch 'IDENTIFIER' 'type declarations must be identifiers.'

   local -- name=$NODE

   mk_typedef
   local -- save=$NODE
   local -n type_=$save

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128
   type_['kind']=$name

   while p_match 'COLON' ; do
      p_typedef
      # shellcheck disable=SC2034
      type_['subtype']=$NODE
   done

   declare -g NODE=$save
}


#───────────────────────────────( expressions )─────────────────────────────────
# Thanks daddy Pratt.
#
# Had to do a little bit of tomfoolery with the binding powers. Shifted
# everything up by 1bp (+2), so the lowest is lbp=3 rbp=4.

declare -gA prefix_binding_power=(
   [MINUS]=9
)
declare -gA NUD=(
   [MINUS]='p_unary'
   [PATH]='p_path'
   [TRUE]='p_boolean'
   [FALSE]='p_boolean'
   [STRING]='p_string'
   [INTEGER]='p_integer'
   [DOLLAR]='p_env_var'
   [PERCENT]='p_int_var'
   [L_BRACKET]='p_array'
)


declare -gA infix_binding_power=(
   [ARROW]='3'
   [DOT]=5
   [CONCAT]=7
)
declare -gA LED=(
   [ARROW]='p_typecast'
   [DOT]='p_index'
   [CONCAT]='p_concat'
)


function p_expression {
   local -i min_bp=${1:-1}

   local op lhs
   local -i lbp=0 rbp=0

   local token="$CURRENT_NAME"
   local type="${CURRENT[type]}"

   local fn="${NUD[$type]}"
   if [[ -z $fn ]] ; then
      # TODO: error reporting
      # This has got to be one of the least helpful error messages here. Woof.
      raise parse_error "not an expression: ${CURRENT[type],,}."
   fi

   p_advance
   $fn "$token" ; lhs=$NODE

   while :; do
      op_type=${CURRENT[type]}

      #───────────────────────────( postfix )───────────────────────────────────
      #lbp=${postfix_binding_power[$op_type]:-0}
      #(( rbp = (lbp == 0 ? 0 : lbp+1) )) ||:

      #if [[ $lbp -ge $min_bp ]] ; then
      #   fn="${RID[${CURRENT[type]}]}"

      #   if [[ ! $fn ]] ; then
      #      raise parse_error "not a postfix expression: ${CURRENT[type],,}."
      #   fi

      #   $fn "$lhs" "$rbp"
      #   lhs="$NODE"

      #   continue
      #fi

      #────────────────────────────( infix )────────────────────────────────────
      lbp=${infix_binding_power[$op_type]:-0}
      (( rbp = (lbp == 0 ? 0 : lbp+1) )) ||:

      if [[ $rbp -lt $min_bp ]] ; then
         break
      fi

      p_advance

      fn=${LED[$op_type]}
      if [[ ! $fn ]] ; then
         raise parse_error "not an infix expression: ${CURRENT[type],,}."
      fi

      $fn  "$lhs"  "$op_type"  "$rbp"
      lhs="$NODE"
   done

   declare -g NODE=$lhs
}


function p_unary {
   local -n prev="$1"
   local -- op="${prev[type]}"

   local -- rbp="${prefix_binding_power[$op]}"

   mk_unary
   local -- save=$NODE
   local -n node=$NODE

   p_expression "$rbp"

   node['op']="$op"
   node['right']="$NODE"

   declare -g NODE=$save
}


function p_concat {
   # String (and path) interpolation are parsed as a high left-associative
   # infix operator.
   #> first (str): "Marcus";
   #> greet (str): "Hello {%first}.";
   #
   # Parses to...
   #> str(value:  "Hello ",
   #>     concat: int_var(value:  first,
   #>                     concat: str(value:  ".",
   #>                                 concat: None)

   # We can safely ignore $2. It's the operator, passed in from p_expression().
   # We already know the operator is a CONCAT.
   local lhs="$1"  _=$2  rbp="$3"

   # To simplify (I think) parsing string/path interpolation, instead of
   # creating a concatentation AST node or some such containing an array of the
   # pieces, each part has a `.concat` key, with the value of the node to
   # concatenate with.
   local -n tail="$lhs"
   until [[ ! ${tail['concat']} ]] ; do
      local -n tail=${tail['concat']}
   done

   p_expression "$rbp"
   tail['concat']=$NODE

   declare -g NODE="$lhs"
}


function p_typecast {
   # Typecasts are a infix operator. The previous lhs is passed in as the
   # 1st argument.
   #
   # Typecasts should have a low binding power, as they must apply to the
   # entirety of the lhs expression, rather than binding to solely the last
   # component of it.
   #
   # Example:
   #> num_times_ten: "{%count}0" -> int;
   #
   # Should compile to  ...  ("" + %count + "0") -> int
   # Rather than        ...  ("" + %count +) ("0" -> int)

   local lhs="$1"

   mk_typecast
   local -- save=$NODE
   local -n node=$NODE

   p_typedef

   node['expr']="$lhs"
   node['typedef']="$NODE"

   declare -g NODE="$lhs"
}


function p_index {
   # We can safely ignore $2. It's the operator, passed in from p_expression().
   # We already know the operator is a CONCAT.
   local lhs="$1"  _=$2  rbp="$3"

   mk_index
   local -- save="$NODE"
   local -n index="$NODE"

   p_expression "$rbp"
   index['left']="$lhs"
   index['right']="$NODE"

   declare -g NODE="$save"
}


function p_array {
   mk_array
   local -- save=$NODE
   local -n node=$NODE

   until p_check 'R_BRACKET' ; do
      p_expression
      node+=( "$NODE" )

      p_check 'R_BRACKET' && break
      p_munch 'COMMA' "array elements must be separated by \`,'."
   done

   p_munch 'R_BRACKET' "array must be closed by \`]'."
   declare -g NODE=$save
}


function p_env_var {
   local -n token="$CURRENT_NAME"
   p_advance # past DOLLAR.

   mk_env_var
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
}


function p_int_var {
   local -n token="$CURRENT_NAME"
   p_advance # past PERCENT.

   mk_int_var
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
}


function p_identifier {
   local -n token="$1"

   mk_identifier
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
}


function p_boolean {
   local -n token="$1"

   mk_boolean
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
}


function p_integer {
   local -n token="$1"

   mk_integer
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
}


function p_string {
   local -n token="$1"

   mk_string
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
   node['concat']=''
   # ^-- for string interpolation, concatenate with the subsequent node. This
   # will appear on each in the chain of linked interpolation nodes.
}


function p_path {
   local -n token="$1"

   mk_path
   local -n node=$NODE
   node['value']=${token[value]}
   node['offset']=${token[offset]}
   node['lineno']=${token[lineno]}
   node['colno']=${token[colno]}
   node['file']=${token[file]}
}
