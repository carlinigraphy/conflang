#!/bin/bash
#
# from ./lexer.sh import {
#  TOKENS[]             # Array of token names
#  TOKEN_$n             # Sequence of all token objects
#  FILE_LINES[]         # INPUT_FILE.readlines()
#  FILES[]              # Array of imported files
# }

#═════════════════════════════════╡ AST NODES ╞═════════════════════════════════
# Must only set the node count on the *first* run. Else we'll overwrite every
# time we import another file.
if [[ ${#FILES[@]} -eq 1 ]] ; then
   declare -gi _NODE_NUM=0
   declare -gi _INCLUDE_NUM=0

   # `include` & `constrain` directives are handled by the parser. They don't
   # actually create any "real" nodes. They leave sentinel values that are later
   # resolved.
   declare -ga INCLUDES=() CONSTRAINTS=()
   # Both hold lists.
   # Sub-objects:
   #> INCLUDES=([0]='INCLUDE_1', [1]='INCLUDE_2')
   #> INCLUDE_1=([path]='./colors.conf' [target]='NODE_01')
   #> INCLUDE_1=([path]='./keybinds.conf' [target]='NODE_25')
   #>
   # Raw values:
   #> CONSTRAINTS=('./subfile1.conf', './subfile2.conf')

   # Saves us from a get_type() function call, or some equivalent.
   declare -gA TYPEOF=()
fi

# Index of currently parsing file.
(( FILE_IDX = ${#FILES[@]} - 1 ))

# Should be reset on every run, as it's unique to this instance of the parser.
declare -g ROOT  # Solely used to indicate the root of the AST.
declare -g NODE
declare -g INCLUDE

# Need to take note of the section.
# `%include` blocks must reference the target Section to include any included
# sub-nodes.
# `%constrain` blocks must check they are not placed anywhere but a top-level
# %inline section.
declare -g SECTION


function mk_decl_section {
   # 1) create parent
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # 1.5) set global SECTION pointer here
   #      for validating %constrain blocks, and setting $target of %include's
   declare -g  SECTION=$nname

   # 2) create list to hold the items within the section.
   (( _NODE_NUM++ ))
   local nname_items="NODE_${_NODE_NUM}"
   declare -ga $nname_items
   local   -n  node_items=$nname_items
   node_items=()

   # 3) assign child node to parent.
   node[name]=
   node[items]=$nname_items

   # 4) Meta information, for easier parsing.
   TYPEOF[$nname]='decl_section'
}


function mk_include {
   (( _INCLUDE_NUM++ ))
   local   --  iname="INCLUDE_${_INCLUDE_NUM}"
   declare -gA $iname
   declare -g  INCLUDE=$iname
   local   -n  include=$iname

   include[path]=
   include[target]=

   INCLUDES+=( $iname )
}


function mk_decl_variable {
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node[name]=       # identifier
   node[type]=       # type
   node[expr]=       # section, array, int, str, bool, path
   node[context]=
   
   TYPEOF[$nname]='decl_variable'
}


function mk_context_block {
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -ga $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node=()

   TYPEOF[$nname]='context_block'
}


function mk_context_test {
   (( _NODE_NUM++ ))
   local   -- nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node[name]=

   TYPEOF[$nname]='context_test'
}


function mk_context_directive {
   (( _NODE_NUM++ ))
   local   -- nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node[name]=

   TYPEOF[$nname]='context_directive'
}


function mk_array {
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -ga $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node=()

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

   (( _NODE_NUM++ ))
   local nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node[kind]=          # Primitive type
   node[subtype]=       # Sub `Type' node

   TYPEOF[$nname]='typedef'
}


function mk_func_call {
   ## psdudo.
   #> class Function:
   #>    name   : identifier = None
   #>    params : array      = []

   # 1) create parent
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # 2) create list to hold the items within the section.
   (( _NODE_NUM++ ))
   local nname_params="NODE_${_NODE_NUM}"
   declare -ga $nname_params
   local   -n  node_params=$nname_params
   node_params=()

   # 3) assign child node to parent.
   node[name]=
   node[params]=$nname_params

   # 4) Meta information, for easier parsing.
   TYPEOF[$nname]='func_call'
}


#function mk_binary {
#   (( _NODE_NUM++ ))
#   local   --  nname="NODE_${_NODE_NUM}"
#   declare -ga $nname
#   declare -g  NODE=$nname
#   local   -n  node=$nname
#
#   node[op]=
#   node[left]=
#   node[right]=
#
#   TYPEOF[$nname]='binary'
#}


function mk_unary {
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node[op]=
   node[right]=

   TYPEOF[$nname]='unary'
}


function mk_boolean {
   (( _NODE_NUM++ ))
   local   -- nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node[value]=
   node[offset]=
   node[lineno]=
   node[colno]=
   node[file]=

   TYPEOF[$nname]='boolean'
}


function mk_integer {
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node[value]=
   node[offset]=
   node[lineno]=
   node[colno]=
   node[file]=

   TYPEOF[$nname]='integer'
}


function mk_string {
   (( _NODE_NUM++ ))
   local   --  nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node[value]=
   node[offset]=
   node[lineno]=
   node[colno]=
   node[file]=

   TYPEOF[$nname]='string'
}


function mk_path {
   (( _NODE_NUM++ ))
   local   -- nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node[value]=
   node[offset]=
   node[lineno]=
   node[colno]=
   node[file]=

   TYPEOF[$nname]='path'
}


function mk_identifier {
   (( _NODE_NUM++ ))
   local   -- nname="NODE_${_NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   # Copied over, so we can ditch the raw tokens after the parser.
   node[value]=
   node[offset]=
   node[lineno]=
   node[colno]=
   node[file]=

   TYPEOF[$nname]='identifier'
}


#═══════════════════════════════════╡ utils ╞═══════════════════════════════════
declare -gi IDX=0
declare -g  CURRENT  CURRENT_NAME
# Calls to `advance' both globally set the name of the current/next node(s),
# e.g., `TOKEN_1', as well as declaring a nameref to the variable itself.


function advance { 
   while [[ $IDX -lt ${#TOKENS[@]} ]] ; do
      declare -g  CURRENT_NAME=${TOKENS[IDX]}
      declare -gn CURRENT=$CURRENT_NAME

      if [[ ${CURRENT[type]} == 'ERROR' ]] ; then
         raise syntax_error "$CURRENT_NAME"
      else
         break
      fi
   done

   (( ++IDX ))
}


function check {
   [[ "${CURRENT[type]}" == $1 ]]
}


function match {
   if check $1 ; then
      advance
      return 0
   fi
   
   return 1
}


function munch {
   local -n t=$CURRENT_NAME

   if ! check $1 ; then
      raise parse_error "[${t[lineno]}:${t[colno]}] $1"
   fi
   
   advance
}


function parse {
   advance
   program
}

#═════════════════════════════╡ GRAMMAR FUNCTIONS ╞═════════════════════════════
function program {
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
   name[value]='%inline'
   name[offset]=0
   name[lineno]=0
   name[colno]=0
   name[file]="${FILE_IDX}"

   mk_decl_section
   declare -g ROOT=$NODE
   local   -n node=$NODE
   local   -n items=${node[items]}

   node[name]=$nname

   while ! check 'EOF' ; do
      statement
      items+=( $NODE )
   done

   munch 'EOF'
}


function statement {
   if match 'PERCENT' ; then
      parser_statement
   else
      declaration
   fi
}


function parser_statement {
   # Saved node referencing the parent Section.
   if match 'INCLUDE' ; then
      include
   elif match 'CONSTRAIN' ; then
      constrain
   else
      raise parse_error "${CURRENT[value]} is not a parser statement."
   fi

   munch 'SEMI' "expecting \`;' after parser statement."
}


function include {
   mk_include
   local -n include=$INCLUDE
   
   path
   munch 'PATH' "expecting path after %include."

   local -n path=$NODE
   include[path]=${path[value]}
   include[target]=$SECTION

   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they
   # do not live past the parser. Need to explicitly set $NODE to an empty
   # string, so they are not appended to the parent's .items[].
}


function constrain {
   local -n section_ptr=$SECTION
   local -n name=${section_ptr[name]}

   if [[ ${name[value]} != '%inline' ]] ; then
      raise parse_error "constrain blocks may only occur in the top level." 
   fi

   if [[ "${#CONSTRAINTS[@]}" -gt 0 ]] ; then
      raise parse_error "may not specify multiple constrain blocks." 
   fi

   munch 'L_BRACKET' "expecting \`[' to begin array of paths."
   while ! check 'R_BRACKET' ; do
      path
      munch 'PATH' "expecting an array of paths."

      local -n path=$NODE
      CONSTRAINTS+=( "${path[value]}" )
   done

   munch 'R_BRACKET' "expecting \`]' after constrain block."
   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they
   # do not live past the parser. Need to explicitly set $NODE to an empty
   # string, so they are not appended to the parent's .items[].
}


function declaration {
   identifier
   munch 'IDENTIFIER' "expecting variable declaration."

   if match 'L_BRACE' ; then
      decl_section
   else
      decl_variable
   fi
}


function decl_section {
   local -- name=$NODE

   mk_decl_section
   local -- save=$NODE
   local -n node=$NODE
   local -n items=${node[items]}

   node[name]=$name

   while ! check 'R_BRACE' ; do
      statement
      items+=( $NODE )
   done

   munch 'R_BRACE' "expecting \`}' after section."
   declare -g NODE=$save
}


function decl_variable {
   # Variable declaration must be preceded by an identifier.
   local -- name=$NODE

   mk_decl_variable
   local -- save=$NODE
   local -n node=$NODE
   node[name]=$name

   # Typedefs.
   if check 'IDENTIFIER' ; then
      typedef
      node[type]=$NODE
   fi

   # Expressions.
   if ! check 'L_BRACE' && ! check 'SEMI' ; then
      expression
      node[expr]=$NODE
   fi

   # Context blocks.
   if match 'L_BRACE' ; then
      context_block
      node[context]=$NODE
   fi

   munch 'SEMI' "expecting \`;' after declaration."
   declare -g NODE=$save
}


function typedef {
   identifier
   munch 'IDENTIFIER' 'expecting identifier for typedef.'

   local -- name=$NODE

   mk_typedef
   local -- save=$NODE
   local -n type_=$save

   type_[kind]=$name

   while match 'COLON' ; do
      typedef
      type_[subtype]=$NODE
   done

   declare -g NODE=$save
}


# THINKIES: I believe a context block can potentially be a postfix expression.
# Though for now, as it only takes single directives and not expressions or
# function calls, it lives here.
function context_block {
   mk_context_block
   local -- save=$NODE
   local -n node=$NODE

   while ! check 'R_BRACE' ; do
      context
      node+=( $NODE )
   done

   munch 'R_BRACE' "expecting \`}' after context block."
   declare -g NODE=$save
}


function context {
   identifier
   munch 'IDENTIFIER' 'expecting identifier in context block.'

   local -- ident=$NODE

   if check 'QUESTION' ; then
      mk_context_test
   else
      mk_context_directive
   fi

   local -n node=$NODE
   node[name]=$ident
}


function array {
   munch 'L_BRACKET'

   mk_array
   local -- save=$NODE
   local -n node=$NODE

   while ! check 'R_BRACKET' ; do
      expression
      node+=( $NODE )
   done

   munch 'R_BRACKET' "expecting \`]' after array."
   declare -g NODE=$save
}


function identifier {
   mk_identifier
   local -n node=$NODE
   node[value]=${CURRENT[value]}
   node[offset]=${CURRENT[offset]}
   node[lineno]=${CURRENT[lineno]}
   node[colno]=${CURRENT[colno]}
   node[file]=${CURRENT[file]}
}


function boolean {
   mk_boolean
   local -n node=$NODE
   node[value]=${CURRENT[value]}
   node[offset]=${CURRENT[offset]}
   node[lineno]=${CURRENT[lineno]}
   node[colno]=${CURRENT[colno]}
   node[file]=${CURRENT[file]}
}


function integer {
   mk_integer
   local -n node=$NODE
   node[value]=${CURRENT[value]}
   node[offset]=${CURRENT[offset]}
   node[lineno]=${CURRENT[lineno]}
   node[colno]=${CURRENT[colno]}
   node[file]=${CURRENT[file]}
}


function string {
   mk_string
   local -n node=$NODE
   node[value]=${CURRENT[value]}
   node[offset]=${CURRENT[offset]}
   node[lineno]=${CURRENT[lineno]}
   node[colno]=${CURRENT[colno]}
   node[file]=${CURRENT[file]}
}


function path {
   mk_path
   local -n node=$NODE
   node[value]=${CURRENT[value]}
   node[offset]=${CURRENT[offset]}
   node[lineno]=${CURRENT[lineno]}
   node[colno]=${CURRENT[colno]}
   node[file]=${CURRENT[file]}
}

#───────────────────────────────( expressions )─────────────────────────────────
# Thanks daddy Pratt.
#
# Had to do a little bit of tomfoolery with the binding powers. Shifted
# everything up by 1bp (+2), so the lowest is lbp=3 rbp=4.

declare -gA prefix_binding_power=(
   [NOT]=10
   [BANG]=10
   [MINUS]=10
)
declare -gA NUD=(
   [NOT]='unary'
   [BANG]='unary'
   [MINUS]='unary'
   [PATH]='path'
   [TRUE]='boolean'
   [FALSE]='boolean'
   [STRING]='string'
   [INTEGER]='integer'
   [IDENTIFIER]='identifier'
   [L_PAREN]='group'
   [L_BRACKET]='array'
)


declare -gA infix_binding_power=(
   [OR]=3
   [AND]=3
   #[EQ]=5
   #[NE]=5
   #[LT]=7
   #[LE]=7
   #[GT]=7
   #[GE]=7
   #[PLUS]=9
   #[MINUS]=9
   #[STAR]=11
   #[SLASH]=11
   [L_PAREN]=13
)
declare -gA LED=(
   [OR]='compop'
   [AND]='compop'
   #[EQ]='binary'
   #[NE]='binary'
   #[LT]='binary'
   #[LE]='binary'
   #[GT]='binary'
   #[GE]='binary'
   #[PLUS]='binary'
   #[MINUS]='binary'
   #[STAR]='binary'
   #[SLASH]='binary'
   [L_PAREN]='func_call'
)


#declare -gA postfix_binding_power=(
#   [L_BRACE]=3
#   [QUESTION]=15
#)
#declare -gA RID=(
#   [L_BRACE]='context_block'
#   [QUESTION]='context_test'
#)


function expression {
   local -i min_bp=${1:-1}

   local -- lhs op
   local -i lbp rbp

   local -- fn=${NUD[${CURRENT[type]}]}

   if [[ -z $fn ]] ; then
      raise parse_error "not an expression: ${CURRENT[type]}."
   fi

   $fn ; lhs=$NODE

   # THINKIES:
   # I feel like there has to be a more elegant way of handling a semicolon
   # ending expressions.
   check 'SEMI' && return
   advance

   while :; do
      op=$CURRENT ot=${CURRENT[type]}

      # If not unset, or explicitly set to 0, `rbp` remains set through each
      # pass of the loop. They are local to the function, but while loops do not
      # have lexical scope. I should've known this. Have done an entire previous
      # project on the premise of lexical scoping in bash.
      rbp=0 ; lbp=${infix_binding_power[ot]:-0}
      (( rbp = (lbp == 0 ? 0 : lbp+1) ))

      if [[ $rbp -lt $min_bp ]] ; then
         break
      fi

      advance

      fn=${LED[${CURRENT[type]}]}
      if [[ -z $fn ]] ; then
         raise parse_error "not an infix expression: ${CURRENT[type]}."
      fi
      $fn  "$lhs"  "$op"  "$rbp"

      lhs=$NODE
   done

   declare -g NODE=$lhs
}


function group {
   expression 
   munch 'R_PAREN' "expecting \`)' after group."
}

function binary {
   local -- lhs="$1" op="$2" rbp="$3"

   mk_binary
   local -- save=$NODE
   local -n node=$NODE

   expression "$rbp"

   node[op]="$op"
   node[left]="$lhs"
   node[right]="$NODE"

   declare -g NODE=$save
}


function unary {
   local -- op="$2" rbp="$3"

   mk_binary
   local -- save=$NODE
   local -n node=$NODE

   expression "$rbp"

   node[op]="$op"
   node[right]="$NODE"

   declare -g NODE=$save
}


#════════════════════════════════════╡ GO ╞═════════════════════════════════════
parse

# If we haven't thrown an exception, I've either catastrophically missed an
# error, or we've completed the run successfully.
PARSE_SUCCESS='yes'

(
   declare -p PARSE_SUCCESS
   declare -p CONSTRAINTS
   declare -p INCLUDES   ${!INCLUDE_*}
   declare -p _NODE_NUM  _INCLUDE_NUM
   declare -p TYPEOF     ROOT
   [[ -n ${!NODE_*} ]] && declare -p ${!NODE_*}
) | sort -V -k3 | sed -E 's;^declare -(-)?;declare -g;'
# It is possible to not use `sed`, and instead read all the sourced declarations
# into an array as strings, and parameter substitution them with something like:
#> shopt -s extglob
#> ${declarations[@]/declare -?(-)/declare -g}
