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
# actually create any "real" nodes. They leave sentinel values that are later
# resolved.
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

# Should be reset on every run, as it's unique to this instance of the parser.
declare -g  ROOT  # Solely used to indicate the root of the AST.
declare -g  NODE
declare -g  INCLUDE

# Need to take note of the section.
# `%include` blocks must reference the target Section to include any included
# sub-nodes.
# `%constrain` blocks must check they are not placed anywhere but a top-level
# %inline section.
declare -g SECTION


function mk_decl_section {
   # 1) create parent
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # 1.5) set global SECTION pointer here
   #      for validating %constrain blocks, and setting $target of %include's
   declare -g  SECTION=$nname

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
   (( INCLUDE_NUM++ ))
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
   node['context']=

   TYPEOF[$nname]='decl_variable'
}


function mk_context_block {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -ga $nname
   declare -g  NODE=$nname

   TYPEOF[$nname]='context_block'
}


function mk_context_test {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['name']=

   TYPEOF[$nname]='context_test'
}


function mk_context_directive {
   (( ++NODE_NUM ))
   local   -- nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['name']=

   TYPEOF[$nname]='context_directive'
}


function mk_array {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -ga $nname
   declare -g  NODE=$nname

   TYPEOF[$nname]='array'
}


function mk_typedef {
   ## psdudo.
   #> class Typedef:
   #>    kind     : identifier = None
   #>    subtype  : Typedef    = None     (opt)
   #
   # Example, representing a list[string]:
   #> Type(
   #>    kind: 'list',
   #>    subtype: Type(
   #>       kind: 'string',
   #>       subtype: None
   #>    )
   #> )

   (( ++NODE_NUM ))
   local nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node['kind']=          # Primitive type
   node['subtype']=       # Sub `Type' node

   TYPEOF[$nname]='typedef'
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
declare -gi IDX=0
declare -g  CURRENT  CURRENT_NAME
# Calls to `advance' both globally set the name of the current/next node(s),
# e.g., `TOKEN_1', as well as declaring a nameref to the variable itself.


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
   [[ "${CURRENT[type]}" == "$1" ]]
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
      items+=( "$NODE" )
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

   p_path
   p_munch 'PATH' "expecting path after %include."

   local -n path=$NODE
   include['path']=${path[value]}
   # shellcheck disable=SC2034 
   # Ignore "appears unused", `shellcheck` doesn't know it's used in a different
   # file.
   include['target']=$SECTION

   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they
   # do not live past the parser. Need to explicitly set $NODE to an empty
   # string, so they are not appended to the parent's .items[].
}


function p_constrain {
   local -n section_ptr=$SECTION
   local -n name=${section_ptr[name]}

   if [[ ${name[value]} != '%inline' ]] ; then
      raise parse_error 'constrain blocks may only occur in the top level.'
   fi

   if [[ "${#CONSTRAINTS[@]}" -gt 0 ]] ; then
      raise parse_error 'may not specify multiple constrain blocks.'
   fi

   p_munch 'L_BRACKET' "expecting \`[' to begin array of paths."
   while ! p_check 'R_BRACKET' ; do
      p_path
      p_munch 'PATH' 'expecting an array of paths.'

      local -n path=$NODE
      CONSTRAINTS+=( "${path[value]}" )
   done

   p_munch 'R_BRACKET' "expecting \`]' after constrain block."
   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they
   # do not live past the parser. Need to explicitly set $NODE to an empty
   # string, so they are not appended to the parent's .items[].
}


function p_declaration {
   p_identifier
   p_munch 'IDENTIFIER' "expecting variable declaration."

   if p_match 'L_BRACE' ; then
      p_decl_section
   else
      p_decl_variable
   fi
}


function p_decl_section {
   local -- name=$NODE

   mk_decl_section
   local -- save=$NODE
   local -n node=$NODE
   local -n items=${node['items']}

   # shellcheck disable=SC2128 
   # Incorrectly identified error by `shellcheck`.
   node['name']="$name"

   while ! p_check 'R_BRACE' ; do
      p_statement
      items+=( "$NODE" )
   done

   p_munch 'R_BRACE' "expecting \`}' after section."
   declare -g NODE=$save
}


function p_decl_variable {
   # Variable declaration must be preceded by an identifier.
   local -- name=$NODE

   mk_decl_variable
   local -- save=$NODE
   local -n node=$NODE

   # shellcheck disable=SC2128
   # Incorrectly identified error by `shellcheck`.
   node['name']=$name

   # Typedefs.
   if p_check 'IDENTIFIER' ; then
      p_typedef
      node['type']=$NODE
   fi

   # Expressions.
   if ! p_check 'L_BRACE' && ! p_check 'SEMI' ; then
      p_expression
      node['expr']=$NODE
   fi

   # Context blocks.
   if p_match 'L_BRACE' ; then
      p_context_block
      node['context']=$NODE
   fi

   p_munch 'SEMI' "expecting \`;' after declaration."
   declare -g NODE=$save
}


function p_typedef {
   p_identifier
   p_munch 'IDENTIFIER' 'expecting identifier for typedef.'

   local -- name=$NODE

   mk_typedef
   local -- save=$NODE
   local -n type_=$save

   # shellcheck disable=SC2128
   # Incorrectly identified error by `shellcheck`.
   type_['kind']=$name

   while p_match 'COLON' ; do
      p_typedef
      # shellcheck disable=SC2034
      type_['subtype']=$NODE
   done

   declare -g NODE=$save
}


# THINKIES: I believe a context block can potentially be a postfix expression.
# Though for now, as it only takes single directives and not expressions or
# function calls, it lives here.
function p_context_block {
   mk_context_block
   local -- save=$NODE
   local -n node=$NODE

   while ! p_check 'R_BRACE' ; do
      p_context
      node+=( "$NODE" )
   done

   p_munch 'R_BRACE' "expecting \`}' after context block."
   declare -g NODE=$save
}


function p_context {
   p_identifier
   p_munch 'IDENTIFIER' 'expecting identifier in context block.'

   local -- ident=$NODE

   if p_check 'QUESTION' ; then
      mk_context_test
   else
      mk_context_directive
   fi

   local -n node=$NODE
   node['name']=$ident
}


function p_array {
   p_munch 'L_BRACKET'

   mk_array
   local -- save=$NODE
   local -n node=$NODE

   until p_check 'R_BRACKET' ; do
      p_expression
      node+=( "$NODE" )
   done

   # TODO: error reporting
   # If the user forgets a closing bracket, the error will be an "invalid
   # expression" from the parser, rather than a specific error pertaining to
   # the array function. I guess this is another problem of not having a
   # specific delimiter between expressions. I think the "simplicity" of my
   # grammar is starting to make parsing and error reporting very difficult.
   # Very similar things are happening with variable declaration syntax.

   declare -g NODE=$save
}


function p_env_var {
   p_munch 'DOLLAR'

   mk_env_var
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
}


function p_int_var {
   p_munch 'PERCENT'

   mk_int_var
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
}


function p_identifier {
   mk_identifier
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
}


function p_boolean {
   mk_boolean
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
}


function p_integer {
   mk_integer
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
}


function p_string {
   mk_string
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
   node['next']=''
   # ^-- for string interpolation, concatenate with the subsequent node.
}


function p_path {
   mk_path
   local -n node=$NODE
   node['value']=${CURRENT[value]}
   node['offset']=${CURRENT[offset]}
   node['lineno']=${CURRENT[lineno]}
   node['colno']=${CURRENT[colno]}
   node['file']=${CURRENT[file]}
}

#───────────────────────────────( expressions )─────────────────────────────────
# Thanks daddy Pratt.
#
# Had to do a little bit of tomfoolery with the binding powers. Shifted
# everything up by 1bp (+2), so the lowest is lbp=3 rbp=4.

declare -gA prefix_binding_power=(
   [MINUS]=10
)
declare -gA NUD=(
   [MINUS]='p_unary'
   [PATH]='p_path'
   [TRUE]='p_boolean'
   [FALSE]='p_boolean'
   [STRING]='p_string'
   [INTEGER]='p_integer'
   [IDENTIFIER]='p_identifier'
   [DOLLAR]='p_env_var'
   [PERCENT]='p_int_var'
   [L_PAREN]='p_group'
   [L_BRACKET]='p_array'
)


#declare -gA infix_binding_power=(
#   [OR]=3
#   [AND]=3
#)
#declare -gA LED=(
#   [OR]='p_compop'
#   [AND]='p_compop'
#)


declare -gA postfix_binding_power=(
   [CONCAT]=15
   [DOT]=17
)
declare -gA RID=(
   [CONCAT]='p_concat'
   [DOT]='p_index'
)


declare -gi _LEVEL=0

function p_expression {
   local -i min_bp=${1:-1}

   local -- lhs op
   local -i lbp=0 rbp=0

   local -- fn=${NUD[${CURRENT[type]}]}

   (( _LEVEL++ ))
   echo " ${_LEVEL} Enter Pratt"            ##DEBUG
   echo "  - ${CURRENT[value]}"  ##DEBUG

   if [[ -z $fn ]] ; then
      # TODO: error reporting
      # This has got to be one of the least helpful error messages here. Woof.
      raise parse_error "not an expression: ${CURRENT[type]}."
   fi

   $fn ; lhs=$NODE

   # THINKIES:
   # I feel like there has to be a more elegant way of handling a semicolon
   # ending expressions.
   p_check 'SEMI' && return
   p_advance

   #declare -p $CURRENT_NAME

   while :; do
      op=$CURRENT ot=${CURRENT[type]}

      #───────────────────────────( postfix )───────────────────────────────────
      lbp=${postfix_binding_power[$ot]:-0}

      if [[ $lbp -ge $min_bp ]] ; then
         fn="${RID[${CURRENT[type]}]}"

         if [[ ! $fn ]] ; then
            raise parse_error "not a postfix expression: ${CURRENT[type]}."
         fi

         $fn "$lhs"
         lhs=$NODE
         continue
      fi

      #────────────────────────────( infix )────────────────────────────────────
      lbp=${infix_binding_power[ot]:-0}
      (( rbp = (lbp == 0 ? 0 : lbp+1) ))

      if [[ $rbp -lt $min_bp ]] ; then
         break
      fi

      p_advance

      fn=${LED[${CURRENT[type]}]}
      if [[ ! $fn ]] ; then
         raise parse_error "not an infix expression: ${CURRENT[type]}."
      fi
      $fn  "$lhs"  "$op"  "$rbp"

      lhs=$NODE
   done

   echo "$_LEVEL ${CURRENT[value]}"
   (( _LEVEL-- ))

   declare -g NODE=$lhs
}


function p_group {
   p_expression
   p_munch 'R_PAREN' "expecting \`)' after group."
}


function p_unary {
   local -- op=${CURRENT[type]}
   local -- rbp="${prefix_binding_power[$op]}"

   p_advance # past operator

   mk_unary
   local -- save=$NODE
   local -n node=$NODE

   # This is a little gimicky. Explanation:
   # We've defined type to be equal to the nameref to the current token's type
   # at the top of the function. When the current token changes, the previously
   # defined `$type` does as well. By re-declaring the variable with the value
   # of itself, it loses the reference.
   local -- op="$op"

   p_expression "$rbp"

   node['op']="$op"
   node['right']="$NODE"

   declare -g NODE=$save
}


function p_concat {
   local -- lname="$1"
   local -n last="$lname"

   p_advance # past the `CONCAT'

   p_expression
   last['next']=$NODE
}


function p_index {
   local -- lname="$1"
   local -n last="$lname"

   p_advance # past the `DOT'

   mk_index
   local -- iname="$NODE"
   local -n index="$iname"

   p_expression
   index['left']="$lname"
   index['right']="$NODE"

   declare -g NODE="$iname"
}
