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
declare -gi  USE_NUM=0

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
 

# Wrapper around the below functions. Just for convenience. Little easier to
# read as well perhaps.
function ast:new { _ast_new_"$1" ;}


function _ast_new_decl_section {
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


function _ast_new_decl_variable {
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


function _ast_new_include {
   (( ++INCLUDE_NUM ))
   local   --  iname="INCLUDE_${INCLUDE_NUM}"
   declare -gA $iname
   declare -g  INCLUDE=$iname
   local   -n  include=$iname

   include['path']=
   include['target']=

   INCLUDES+=( "$iname" )
}


function _ast_new_use {
   (( ++USE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['path']=       # the 'path' to the module
   node['name']=       # identifier, if using `as $ident;`

   TYPEOF[$nname]='use'
}


function _ast_new_array {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -ga $nname
   declare -g  NODE=$nname

   TYPEOF[$nname]='array'
}


function _ast_new_typedef {
   (( ++NODE_NUM ))
   local nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node['kind']=          # Primitive type
   node['subtype']=       # Sub `Type' node

   TYPEOF[$nname]='typedef'
}


function _ast_new_typecast {
   (( ++NODE_NUM ))
   local nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname

   local -n node=$nname
   node['expr']=
   node['typedef']=

   TYPEOF[$nname]='typecast'
}


function _ast_new_member {
   # Only permissible in accessing section keys. Not in array indices.

   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['left']=
   node['right']=

   TYPEOF[$nname]='member'
}


function _ast_new_index {
   # Only permissible in accessing array indices. Not in sections.

   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['left']=
   node['right']=

   TYPEOF[$nname]='index'
}


function _ast_new_unary {
   (( ++NODE_NUM ))
   local   --  nname="NODE_${NODE_NUM}"
   declare -gA $nname
   declare -g  NODE=$nname
   local   -n  node=$nname

   node['op']=
   node['right']=

   TYPEOF[$nname]='unary'
}


function _ast_new_boolean {
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


function _ast_new_integer {
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


function _ast_new_string {
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


function _ast_new_path {
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


function _ast_new_identifier {
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


function _ast_new_env_var {
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


#═══════════════════════════════════╡ utils ╞═══════════════════════════════════
function parser:init {
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


function parser:advance {
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


function parser:check {
   # Allows for passing in something like: "L_BRACKET,STRING,INTEGER" to check
   # multiple tokens.
   [[ ,"$1", ==  *,${CURRENT[type]},* ]]
}


function parser:match {
   if parser:check "$1" ; then
      parser:advance
      return 0
   fi

   return 1
}


function parser:munch {
   if ! parser:check "$1" ; then
      raise munch_error  "$1"  "$CURRENT_NAME"  "$2"
   fi

   parser:advance
}


function parser:parse {
   # Realistically this should not happen, outside running the lexer & parser
   # independently. Though it's a prerequisite for all that follows.
   if [[ "${#TOKENS[0]}" -eq 0 ]] ; then
      raise parse_error "didn't receive tokens from lexer."
   fi

   parser:advance
   parser:program
}

#═════════════════════════════╡ GRAMMAR FUNCTIONS ╞═════════════════════════════
function parser:program {
   # This is preeeeeeeeeeeeetty janky. I don't love it. Since this pseudo-
   # section doesn't actually exist in-code, it doesn't have any opening or
   # closing braces. So `section()` gets fucked up when trying to munch a
   # closing brace. Gotta just in-line stuff here all hacky-like.
   #
   # Creates a default top-level `section', allowing top-level key:value pairs,
   # wout requiring a dict (take that, JSON).
   ast:new identifier

   local -- nname=$NODE
   local -n name=$nname
   name['value']='%inline'
   name['offset']=0
   name['lineno']=0
   name['colno']=0
   name['file']="${FILE_IDX}"

   ast:new decl_section

   # shellcheck disable=SC2034
   declare -g ROOT=$NODE
   local   -n node=$NODE
   local   -n items=${node['items']}

   node['name']=$nname

   while ! parser:check 'EOF' ; do
      parser:statement

      # %include/%constrain are statements, but do not have an associated $NODE.
      # Need to avoid adding an empty string to the section.items[]
      if [[ $NODE ]] ; then
         items+=( "$NODE" )
      fi
   done

   parser:munch 'EOF'
}


function parser:statement {
   if parser:match 'PERCENT' ; then
      parser:parser_statement
   else
      parser:declaration
   fi
}


function parser:parser_statement {
   # Saved node referencing the parent Section.
   if   parser:match 'INCLUDE'   ; then parser:include
   elif parser:match 'CONSTRAIN' ; then parser:constrain
   elif parser:match 'USE'       ; then parser:use
   else
      raise parse_error "${CURRENT[value]} is not a parser statement."
   fi

   parser:munch 'SEMI' "expecting \`;' after parser statement."
}


function parser:include {
   ast:new include
   local -n include=$INCLUDE

   # When used outside the `parser:expression()` function, need to explicitly
   # pass in a refernce to the current token.
   parser:path "$CURRENT_NAME"
   parser:munch 'PATH' "expecting path after %include."

   local -n path=$NODE
   # shellcheck disable=SC2034 
   include['path']=${path[value]}
   include['target']=$SECTION

   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they do
   # not live past the parser.
}


function parser:constrain {
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
   # This should probably just call `parser:array`. Then we can pull the paths
   # out from within it? Rearpb making it a special case. Or maybe just
   # straight up call `parser:expression`. Hmm.
   parser:munch 'L_BRACKET' "expecting \`[' to begin array of paths."
   until parser:check 'R_BRACKET' ; do
      # When used outside the `parser:expression()` function, need to explicitly
      # pass in a refernce to the current token.
      parser:path "$CURRENT_NAME"
      parser:munch 'PATH' 'expecting an array of paths.'

      local -n path=$NODE
      CONSTRAINTS+=( "${path[value]}" )

      parser:check 'R_BRACKET' && break
      parser:munch 'COMMA' "array elements must be separated by \`,'."
   done

   parser:munch 'R_BRACKET' "expecting \`]' after constrain block."
   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they do
   # not live past the parser.
}


#function parser:use {
#   local -n section_ptr=$SECTION
#   local -n name=${section_ptr[name]}
#
#   if [[ ${name[value]} != '%inline' ]] ; then
#      raise parse_error '%use may not occur in a section.'
#   fi
#
#   ast:new use
#   local -- save="$NODE"
#   local -n use="$NODE"
#
#   parser:path "$CURRENT_NAME"
#   parser:munch 'PATH' "expecting a module path."
#   local path="$NODE"
#
#   if parser:match 'AS' ; then
#      parser:identifier "$CURRENT_NAME"
#      parser:munch 'IDENTIFIER'
#      local name="$NODE"
#   fi
#
#   use['path']="$path"
#   use['name']="$name"
#
#   declare -g NODE="$save"
#}


function parser:declaration {
   parser:identifier "$CURRENT_NAME"
   parser:munch 'IDENTIFIER' "expecting variable declaration."

   if parser:match 'L_BRACE' ; then
      parser:decl_section
   else
      parser:decl_variable
   fi
}


function parser:decl_section {
   local -- name=$NODE
   local -- sect=$SECTION

   ast:new decl_section
   local -- save=$NODE
   local -n node=$NODE
   local -n items=${node['items']}

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128 
   node['name']="$name"

   while ! parser:check 'R_BRACE' ; do
      parser:statement

      # %include/%constrain are statements, but do not have an associated $NODE.
      # Need to avoid adding an empty string to the section.items[]
      if [[ $NODE ]] ; then
         items+=( "$NODE" )
      fi
   done

   parser:munch 'R_BRACE' "expecting \`}' after section."
   declare -g NODE="$save"
   declare -g SECTION="$sect"
}


function parser:decl_variable {
   # Variable declaration must be preceded by an identifier.
   local -- name=$NODE

   ast:new decl_variable
   local -- save=$NODE
   local -n node=$NODE

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128
   node['name']=$name

   # Typedefs.
   if parser:match 'L_PAREN' ; then
      parser:typedef
      parser:munch 'R_PAREN' "typedef must be closed by \`)'."
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
   if parser:match 'COLON' ; then
      parser:expression
      node['expr']=$NODE
   elif parser:match "$expr_str" ; then
      raise parse_error "expecting \`:' before expression."
   fi

   parser:munch 'SEMI' "expecting \`;' after declaration."
   declare -g NODE=$save
}


function parser:typedef {
   parser:identifier "$CURRENT_NAME"
   parser:munch 'IDENTIFIER' 'type declarations must be identifiers.'

   local -- name=$NODE

   ast:new typedef
   local -- save=$NODE
   local -n type_=$save

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128
   type_['kind']=$name

   while parser:match 'COLON' ; do
      parser:typedef
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
#
# Priority (lowest to highest)
#  ->       type casts                 3
#   -       unary minus                5
#   [       array index                7
#   .       member index               9
# N/A       string concatenation       11

declare -gA prefix_binding_power=(
   [MINUS]=5
)
declare -gA NUD=(
   [L_PAREN]='parser:grouping'
   [MINUS]='parser:unary'
   [PATH]='parser:path'
   [TRUE]='parser:boolean'
   [FALSE]='parser:boolean'
   [STRING]='parser:string'
   [INTEGER]='parser:integer'
   [DOLLAR]='parser:env_var'
   [L_BRACKET]='parser:array'
   [IDENTIFIER]='parser:identifier'
)


declare -gA infix_binding_power=(
   [ARROW]='3'
   [DOT]=9
   [CONCAT]=11
)
declare -gA LED=(
   [ARROW]='parser:typecast'
   [DOT]='parser:member'
   [CONCAT]='parser:concat'
)


declare -gA postfix_binding_power=(
   [L_BRACKET]='7'
)
declare -gA RID=(
   [L_BRACKET]='parser:index'
)


function parser:expression {
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

   parser:advance
   $fn "$token" ; lhs=$NODE

   while :; do
      op_type=${CURRENT[type]}

      #───────────────────────────( postfix )───────────────────────────────────
      lbp=${postfix_binding_power[$op_type]:-0}
      (( rbp = (lbp == 0 ? 0 : lbp+1) )) ||:

      if [[ $lbp -ge $min_bp ]] ; then
         fn="${RID[${CURRENT[type]}]}"

         if [[ ! $fn ]] ; then
            raise parse_error "not a postfix expression: ${CURRENT[type],,}."
         fi

         $fn "$lhs" "$rbp"
         lhs="$NODE"

         continue
      fi

      #────────────────────────────( infix )────────────────────────────────────
      lbp=${infix_binding_power[$op_type]:-0}
      (( rbp = (lbp == 0 ? 0 : lbp+1) )) ||:

      if [[ $rbp -lt $min_bp ]] ; then
         break
      fi

      parser:advance

      fn=${LED[$op_type]}
      if [[ ! $fn ]] ; then
         raise parse_error "not an infix expression: ${CURRENT[type],,}."
      fi

      $fn  "$lhs"  "$op_type"  "$rbp"
      lhs="$NODE"
   done

   declare -g NODE=$lhs
}


function parser:grouping {
   parser:expression
   parser:munch 'R_PAREN' "grouping must be closed by \`)'."
}


function parser:unary {
   local -n prev_r="$1"
   local op="${prev_r[type]}"
   local rbp="${prefix_binding_power[$op]}"

   ast:new unary
   local node="$NODE"
   local -n node_r="$node"

   parser:expression "$rbp"

   node_r['op']="$op"
   node_r['right']="$NODE"

   declare -g NODE="$node"
}


function parser:concat {
   # String (and path) interpolation are parsed as a high left-associative
   # infix operator.
   #> first (str): "Marcus";
   #> greet (str): "Hello {first}.";
   #
   # Parses to...
   #> str(value:  "Hello ",
   #>     concat: ident(value:  first,
   #>                   concat: str(value:  ".",
   #>                               concat: None)

   # We can safely ignore $2. It's the operator, passed in from
   # parser:expression(). We already know the operator is a CONCAT.
   local lhs="$1"  _=$2  rbp="$3"

   # To simplify (I think) parsing string/path interpolation, instead of
   # creating a concatentation AST node or some such containing an array of the
   # pieces, each part has a `.concat` key, with the value of the node to
   # concatenate with.
   local -n tail="$lhs"
   until [[ ! ${tail['concat']} ]] ; do
      local -n tail=${tail['concat']}
   done

   parser:expression "$rbp"
   tail['concat']=$NODE

   declare -g NODE="$lhs"
}


function parser:typecast {
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
   #
   local lhs="$1"

   ast:new typecast
   local node="$NODE"
   local -n node_r="$node"

   parser:typedef
   node_r['expr']="$lhs"
   node_r['typedef']="$NODE"

   declare -g NODE="$node"
}


function parser:index {
   local lhs="$1"  _="$2"
   parser:advance # past L_BRACKET.

   ast:new index
   local -- save="$NODE"
   local -n index="$NODE"

   parser:expression
   index['left']="$lhs"
   index['right']="$NODE"

   parser:munch 'R_BRACKET' "array must be closed by \`]'."
   declare -g NODE="$save"
}


function parser:member {
   local lhs="$1"  _=$2  rbp="$3"
                    # ^-- ignore `.` operator
   ast:new member
   local -- node="$NODE"
   local -n node_r="$NODE"

   parser:identifier "$CURRENT_NAME"
   parser:munch 'IDENTIFIER'
   # TODO(error reporting):
   # Include more helpful information. Check if it's an INTEGER, suggest they
   # instead use [int].

   node_r['left']="$lhs"
   node_r['right']="$NODE"

   declare -g NODE="$node"
}


function parser:array {
   ast:new array
   local -- save=$NODE
   local -n node=$NODE

   until parser:check 'R_BRACKET' ; do
      parser:expression
      node+=( "$NODE" )

      parser:check 'R_BRACKET' && break
      parser:munch 'COMMA' "array elements must be separated by \`,'."
   done

   parser:munch 'R_BRACKET' "array must be closed by \`]'."
   declare -g NODE=$save
}


function parser:env_var {
   local -n token="$CURRENT_NAME"
   parser:advance # past DOLLAR.

   ast:new env_var
   local -n node=$NODE

   # Copy over params from the token -> AST node.
   for param in value offset lineno colno file ; do
      node[$param]="${token[$param]}"
   done
}


function parser:identifier {
   local -n token="$1"

   ast:new identifier
   local -n node=$NODE

   # Copy over params from the token -> AST node.
   for param in value offset lineno colno file ; do
      node[$param]="${token[$param]}"
   done
}


function parser:boolean {
   local -n token="$1"

   ast:new boolean
   local -n node=$NODE

   # Copy over params from the token -> AST node.
   for param in value offset lineno colno file ; do
      node[$param]="${token[$param]}"
   done
}


function parser:integer {
   local -n token="$1"

   ast:new integer
   local -n node=$NODE

   # Copy over params from the token -> AST node.
   for param in value offset lineno colno file ; do
      node[$param]="${token[$param]}"
   done
}


function parser:string {
   local -n token="$1"

   ast:new string
   local -n node=$NODE
   node['concat']=''
   # ^-- for string interpolation, concatenate with the subsequent node. This
   # will appear on each in the chain of linked interpolation nodes.

   # Copy over params from the token -> AST node.
   for param in value offset lineno colno file ; do
      node[$param]="${token[$param]}"
   done
}


function parser:path {
   local -n token="$1"

   ast:new path
   local -n node=$NODE
   node['concat']=''
   # ^-- for string interpolation, concatenate with the subsequent node. This
   # will appear on each in the chain of linked interpolation nodes.

   # Copy over params from the token -> AST node.
   for param in value offset lineno colno file ; do
      node[$param]="${token[$param]}"
   done
}
