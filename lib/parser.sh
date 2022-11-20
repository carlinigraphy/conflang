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
#declare -gi USE_NUM=0

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
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   # Set global SECTION pointer here for validating %constrain blocks, and
   # setting $target of %include's
   declare -g SECTION="$node"

   # 2) create list to hold the items within the section.
   (( ++NODE_NUM ))
   local items="NODE_${NODE_NUM}"
   declare -ga "$items"

   # 3) assign child node to parent.
   local -n node_r="$node"
   node_r['items']="$items"
   node_r['name']=''

   # Leaf nodes (anything that may not *contain* another node) carries along
   # the $LOCATION node from its parent $TOKEN. For debugging, non-leaf nodes
   # need to pull their own .start_{ln,col} and .end_{ln,col} from their
   # associated $TOKEN.
   location:new
   node_r['location']="$LOCATION"

   # 4) Meta information, for easier parsing.
   TYPEOF["$node"]='decl_section'
}


function _ast_new_decl_variable {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['name']=''                      # AST(identifier)
   node_r['type']=''                      # AST(type)
   node_r['expr']=''                      # AST(array, int, str, ...)

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='decl_variable'
}


function _ast_new_include {
   (( ++INCLUDE_NUM ))
   local node="INCLUDE_${INCLUDE_NUM}"
   declare -gA "$node"
   declare -g INCLUDE="$node"

   local -n node_r="$node"
   node_r['path']=''
   node_r['target']=''

   location:new
   node_r['location']="$LOCATION"

   INCLUDES+=( "$node" )
}


# NYI
#
#function _ast_new_use {
#   (( ++USE_NUM ))
#   local node="NODE_${NODE_NUM}"
#   declare -gA "$node"
#   declare -g NODE="$node"
#
#   local -n node_r="$node"
#   node_r['path']=       # the 'path' to the module
#   node_r['name']=       # identifier, if using `as $ident;`
#
#   location:new
#   node_r['location']="$LOCATION"
#
#   TYPEOF["$node"]='use'
#}


function _ast_new_array {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   # Similar to sections, arrays need a .items property to hold their values.
   (( ++NODE_NUM ))
   local items="NODE_${NODE_NUM}"
   declare -ga "$items"

   # Assign .items node.
   local -n node_r="$node"
   node_r['items']="$items"

   # Assign .location node.
   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='array'
}


function _ast_new_typedef {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['kind']=''        # Primitive type
   node_r['subtype']=''     # Sub `Type' node

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='typedef'
}


function _ast_new_typecast {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g  NODE="$node"

   local -n node_r="$node"
   node_r['expr']=''
   node_r['typedef']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='typecast'
}


function _ast_new_member {
   # Only permissible in accessing section keys. Not in array indices.

   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['left']=''
   node_r['right']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='member'
}


function _ast_new_index {
   # Only permissible in accessing array indices. Not in sections.

   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['left']=''
   node_r['right']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='index'
}


function _ast_new_unary {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['op']=''
   node_r['right']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='unary'
}


function _ast_new_boolean {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='boolean'
}


function _ast_new_integer {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='integer'
}


function _ast_new_string {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='string'
}


function _ast_new_path {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='path'
}


function _ast_new_identifier {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   # shellcheck disable=SC2034
   TYPEOF["$node"]='identifier'
}


function _ast_new_env_var {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   # shellcheck disable=SC2034
   TYPEOF["$node"]='env_var'
}


#═══════════════════════════════════╡ utils ╞═══════════════════════════════════
function parser:init {
   declare -gi IDX=0
   declare -g  CURRENT=''  CURRENT_NAME=''
   # Calls to `advance' both globally set the name of the current/next node(s),
   # e.g., `TOKEN_1', as well as declaring a nameref to the variable itself.

   declare -g  ROOT=''        #< Root of this tree
   declare -g  NODE=''        #< Last generated AST node
   declare -g  INCLUDE=''     #< 

   # Need to take note of the section.
   # `%include` blocks must reference the target Section to include any included
   # sub-nodes.
   # `%constrain` blocks must check they are not placed anywhere but a top-level
   # %inline section.
   declare -g SECTION=''
}


function parser:advance {
   if (( $IDX -lt ${#TOKENS[@]} )) ; then
      declare -g  CURRENT_NAME="${TOKENS[$IDX]}"
      declare -gn CURRENT="$CURRENT_NAME"

      (( ++IDX ))

      if [[ ${CURRENT[type]} == ERROR ]] ; do
         parser:advance
      done
   fi

   if [[ $PANICKING != true ]] ; then
      return
   fi

   # TODO: rethink this section, slammed it out right now for notes.
   until [[ ${CURRENT[type]} == SEMI ]] ; do
      parser:advance
   done
   declare -g PANICKING=false
}


function parser:check {
   # Is $CURRENT one of a comma-delimited list of types.
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
      e=( munch_error
         --origin "$CURRENT_NAME"
         --caught "$CURRENT_NAME"
         "expecting [$1], got [${CURRENT[type],,}], $2"
      ); raise "${e[@]}"
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
   local ident="$NODE"
   local -n ident_r="$ident"
   ident_r['value']='%inline'

   local -n loc_r="$LOCATION"
   loc_r['start_ln']=0
   loc_r['start_col']=0
   loc_r['file']="$FILE_IDX"

   # Section declaration itself.
   ast:new decl_section
   declare -g ROOT="$NODE"
   local node="$NODE"
   local -n node_r="$node"
   node_r['name']="$ident"

   local -n loc_r="$LOCATION"
   loc_r['start_ln']=0
   loc_r['start_col']=0
   loc_r['file']="$FILE_IDX"

   local -n items=${node_r['items']}
   while ! parser:check 'EOF' ; do
      parser:statement
      # %include/%constrain are statements, but do not have an associated $NODE.
      # Need to avoid adding an empty string to the section.items[]
      if [[ $NODE ]] ; then
         items+=( "$NODE" )
      fi
   done

   parser:munch 'EOF'
   location:copy "$CURRENT_NAME"  "$node"  'end_ln'  'end_col'
}


function parser:statement {
   if parser:match 'PERCENT' ; then
      parser:parser_statement
   else
      parser:declaration
   fi
}


function parser:parser_statement {
   if   parser:match 'INCLUDE'   ; then parser:include
   elif parser:match 'CONSTRAIN' ; then parser:constrain
   else
      e=( parse_error
         --caught "$CURRENT_NAME"
         --origin "$CURRENT_NAME"
         "invalid directive [${CURRENT[value]}]"
      ); raise "${e[@]}"
   fi

   parser:munch 'SEMI' "expecting \`;' after directive."
}


function parser:include {
   # TODO(refactor): this shouldn't be an `ast:__` fn. Include statements don't
   # go onto the AST.
   ast:new include
   local include="$INCLUDE"
   local -n include_r="$include"

   # When used outside the `parser:expression()` function, need to explicitly
   # pass in a refernce to the current token.
   parser:path "$CURRENT_NAME"
   parser:munch 'PATH' "expecting path after %include."

   local -n path="$NODE"
   # shellcheck disable=SC2034
   include['path']="${path[value]}"
   include['target']="$SECTION"

   declare -g NODE=
   # Section declarations loop & append $NODEs to their .items. `include`/
   # `constrain` directives are technically children of a section, but they do
   # not live past the parser.
}


function parser:constrain {
   local -n section_ptr=$SECTION
   local -n name=${section_ptr[name]}

   if [[ ${name[value]} != '%inline' ]] ; then
      e=( parse_error
         --caught "$CURRENT_NAME"
         --origin "$CURRENT_NAME"
         '%constrain may not occur in a section'
      ); raise "${e[@]}"
   fi

   if [[ ${name[file]} -ne 0 ]] ; then
      e=( parse_error
         --caught "$CURRENT_NAME"
         --origin "$CURRENT_NAME"
         '%constrain may not occur in a sub-file'
      ); raise "${e[@]}"
   fi

   if [[ "${#CONSTRAINTS[@]}" -gt 0 ]] ; then
      e=( parse_error
         --caught "$CURRENT_NAME"
         --origin "$CURRENT_NAME"
         'may not specify multiple constrain blocks'
      ); raise "${e[@]}"
   fi

   parser:munch 'L_BRACKET' "expecting \`[' to begin array of paths."
   until parser:check 'R_BRACKET' ; do
      parser:path "$CURRENT_NAME"
      parser:munch 'PATH'

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
#   local save="$NODE"
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
   local ident="$NODE"
   local sect="$SECTION"

   ast:new decl_section
   local node="$NODE"
   local -n node_r="$node"
   node_r['name']="$ident"

   local -n items_r="${node_r['items']}"
   while ! parser:check 'R_BRACE' ; do
      parser:statement
      # Ignore %-directives, they generate an empty NODE.
      if [[ $NODE ]] ; then
         items_r+=( "$NODE" )
      fi
   done

   local close="$CURRENT_NAME"
   parser:munch 'R_BRACE' "expecting \`}' after section."

   location:copy "$ident"  "$node"  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'end_ln'    'end_col'

   declare -g NODE="$node"
   declare -g SECTION="$sect"
}


function parser:decl_variable {
   # Variable declaration must be preceded by an identifier.
   local ident="$NODE"

   ast:new decl_variable
   local node="$NODE"
   local -n node_r="$node"

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128
   node_r['name']="$ident"

   # Typedefs.
   #
   # For error reporting, pass the location of the L_PAREN in for the Typedef
   # LOCATION node.
   local _open="$CURRENT_NAME"
   if parser:match 'L_PAREN' ; then
      parser:typedef
      node_r['type']="$NODE"

      local _close="$CURRENT_NAME"
      parser:munch 'R_PAREN' "typedef must be closed by \`)'."

      location:copy "$_open"   "$NODE"  'start_ln'  'start_col'
      location:copy "$_close"  "$NODE"  'end_ln'    'end_col'
   fi

   # If current token is one that begins an expression, advise they likely
   # indended a colon before it.
   local expr_types=''
   for expr in "${!NUD[@]}" ; do
      expr_types="${expr_str:+,}${expr}"
   done

   # Expressions.
   if parser:match 'COLON' ; then
      parser:expression
      node_r['expr']=$NODE
   elif parser:match "$expr_types" ; then
      e=( parse_error
         --origin "$node"
         --caught "$CURRENT_NAME"
         "expecting \`:' before expression"
      ); raise "${e[@]}"
   fi

   local close="$CURRENT_NAME"
   parser:munch 'SEMI' "expecting \`;' after declaration."

   location:copy "$ident"  "$node"  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'end_ln'    'end_col'

   declare -g NODE="$node"
}


function parser:typedef {
   parser:identifier "$CURRENT_NAME"
   parser:munch 'IDENTIFIER' 'type declarations must be identifiers.'
   local ident="$NODE"

   ast:new typedef
   local node="$NODE"
   local -n node_r="$node"
   node_r['kind']="$ident"

   while parser:match 'COLON' ; do
      parser:typedef "$open"
      node_r['subtype']="$NODE"
   done

   declare -g NODE="$node"
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
      e=( parse_error
         --origin "$token"
         --caught "$token"
         "not an expression [${CURRENT[type],,}]"
      ); raise "${e[@]}"
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
            e=( parse_error
               --origin "$token"
               --caught "$token"
               "not a postfix expression [${CURRENT[type],,}]"
            ); raise "${e[@]}"
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
         e=( parse_error
            --origin "$token"
            --caught "$token"
            "not an infix expression [${CURRENT[type],,}]"
         ); raise "${e[@]}"
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
   local prev="$1"

   local -n prev_r="$prev"
   local op="${prev_r[type]}"
   local rbp="${prefix_binding_power[$op]}"

   ast:new unary
   local node="$NODE"
   local -n node_r="$node"

   parser:expression "$rbp"

   node_r['op']="$op"
   node_r['right']="$NODE"

   location:copy "$prev"   "$node"  'start_ln'  'start_col'
   location:copy "$NODE"   "$node"  'end_ln'    'end_col'

   declare -g NODE="$node"
}


function parser:concat {
   # String (and path) interpolation are parsed as a high left-associative
   # infix operator.

   local lhs="$1"  _=$2  rbp="$3"
                    # ^-- ignore operator

   local -n node_r="$lhs"
   until [[ ! "${node_r[concat]}" ]] ; do
      local -n node_r="${node_r[concat]}"
   done

   parser:expression "$rbp"
   node_r['concat']=$NODE

   location:copy "$lhs"   "$node"  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'end_ln'    'end_col'

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

   location:copy "$lhs"   "$node"  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'end_ln'    'end_col'

   declare -g NODE="$node"
}


function parser:index {
   local lhs="$1"  _="$2"
                     # ^-- ignore rbp

   parser:advance # past L_BRACKET.

   ast:new index
   local save="$NODE"
   local -n index="$NODE"

   parser:expression
   index['left']="$lhs"
   index['right']="$NODE"

   local close="$CURRENT_NAME"
   parser:munch 'R_BRACKET' "index must be closed by \`]'."

   location:copy "$lhs"    "$node"  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'end_ln'    'end_col'

   declare -g NODE="$save"
}


function parser:member {
   local lhs="$1"  _=$2  rbp="$3"
                    # ^-- ignore `.` operator
   ast:new member
   local node="$NODE"
   local -n node_r="$node"

   parser:identifier "$CURRENT_NAME"
   parser:munch 'IDENTIFIER'
   # TODO(error reporting):
   # Include more helpful information. Check if it's an INTEGER, suggest they
   # instead use [int].

   node_r['left']="$lhs"
   node_r['right']="$NODE"

   location:copy "$lhs"   "$node"  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'end_ln'    'end_col'

   declare -g NODE="$node"
}


function parser:array {
   # The opening `[` Token, for LOCATION informatino.
   local open="$1"

   ast:new array
   local node="$NODE"
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   until parser:check 'R_BRACKET' ; do
      parser:expression
      items_r+=( "$NODE" )

      parser:check 'R_BRACKET' && break
      parser:munch 'COMMA' "array elements must be separated by \`,'."
   done

   local close="$CURRENT_NAME"
   parser:munch 'R_BRACKET' "array must be closed by \`]'."

   location:copy "$open"   "$node"  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'end_ln'    'end_col'

   declare -g NODE="$node"
}


function parser:env_var {
   local -n token_r="$CURRENT_NAME"
   parser:advance # past DOLLAR.

   ast:new env_var
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
}


function parser:identifier {
   local -n token="$1"
   local -n token_r="$CURRENT_NAME"

   ast:new identifier
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
}


function parser:boolean {
   local -n token_r="$1"

   ast:new boolean
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
}


function parser:integer {
   local -n token_r="$1"

   ast:new integer
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
}


function parser:string {
   local -n token_r="$1"

   ast:new string
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
   node_r['concat']=''
   # ^-- for string interpolation, concatenate with the subsequent node. This
   # will appear on each in the chain of linked interpolation nodes.
}


function parser:path {
   local -n token_r="$1"

   ast:new path
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
   node_r['concat']=''
   # ^-- for string interpolation, concatenate with the subsequent node. This
   # will appear on each in the chain of linked interpolation nodes.
}
