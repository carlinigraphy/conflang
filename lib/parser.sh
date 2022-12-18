#!/bin/bash

#===============================================================================
# @section                            AST
# @description               Generating tree nodes.
#-------------------------------------------------------------------------------

# ast:new()
# @description
#  Helper function wrapping all the below AST node creation functions.
#
# @arg   $1    :str     AST node's name to create
function ast:new { _ast_new_"$1" ;}


function _ast_new_program {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$NODE"
   node_r['header']=
   node_r['container']=

   TYPEOF["$node"]='program'
}


function _ast_new_header {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   (( ++_NODE_NUM ))
   local items="NODE_${_NODE_NUM}"
   declare -ga "$items"

   # Assign .items node.
   local -n node_r="$node"
   node_r['items']="$items"

   # Assign .location node.
   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='header'
}


function _ast_new_import {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['path']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='import'
}


# _ast_new_typedef
# @description
#  Called as `ast:new typedef`
#
# @set   LOCATION
# @set   NODE
# @set   TYPEOF{}
#
# @see   ast:new
# @see   _ast_new_type
# @see   parser:type
# @noargs
function _ast_new_typedef {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['type']=''
   node_r['name']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='typedef'
}


function _ast_new_container {
   ast:new identifier                  # name:  %container
   local ident="$NODE"
   local -n ident_r="$ident"
   ident_r['value']='%container'

   location:new
   local -n loc_r="$LOCATION"          #--^ name's location info
   loc_r['start_ln']=1
   loc_r['start_col']=1
   loc_r['end_ln']=1
   loc_r['end_col']=1

   local -n file_r="$FILE"
   loc_r['file']="${file_r[path]}"

   ast:new decl_section                # section:  %container
   local node="$NODE"
   local -n node_r="$node"
   node_r['name']="$ident"

   location:new                        #--^ section's location info
   local -n loc_r="$LOCATION"
   loc_r['start_ln']=1
   loc_r['start_col']=1
   loc_r['file']="${file_r[path]}"
}


function _ast_new_decl_section {
   # 1) create section container
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   # 2) create list to hold the items within the section.
   (( ++_NODE_NUM ))
   local items="NODE_${_NODE_NUM}"
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
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['name']=''                      # AST(identifier)
   node_r['type']=''                      # AST(type)
   node_r['expr']=''                      # AST(list, int, str, ...)

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='decl_variable'
}


function _ast_new_list {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   # Similar to sections, lists need a .items property to hold their values.
   (( ++_NODE_NUM ))
   local items="NODE_${_NODE_NUM}"
   declare -ga "$items"

   # Assign .items node.
   local -n node_r="$node"
   node_r['items']="$items"

   # Assign .location node.
   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='list'
}


function _ast_new_type {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['kind']=''

   # Array to hold subtypes. Example:
   #> rec[str, int]
   (( ++_NODE_NUM ))
   local subtype="NODE_${_NODE_NUM}"
   declare -ga "$subtype"
   node_r['subtype']="$subtype"

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='type'
}


function _ast_new_typecast {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g  NODE="$node"

   local -n node_r="$node"
   node_r['expr']=''
   node_r['type']=''

   location:new
   node_r['location']="$LOCATION"

   TYPEOF["$node"]='typecast'
}


function _ast_new_member {
   # Only permissible in accessing section keys. Not in list indices.

   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
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
   # Only permissible in accessing list indices. Not in sections.

   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
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
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
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
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='boolean'
}


function _ast_new_integer {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='integer'
}


function _ast_new_string {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='string'
}


function _ast_new_path {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='path'
}


function _ast_new_identifier {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='identifier'
}


function _ast_new_env_var {
   (( ++_NODE_NUM ))
   local node="NODE_${_NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['value']=''
   node_r['location']=''

   TYPEOF["$node"]='env_var'
}


#===============================================================================
# @section                        Parser utils
#-------------------------------------------------------------------------------

# location:new()
# @set   LOCATION
# @noargs
function location:new {
   (( ++_LOC_NUM ))
   local loc="LOC_${_LOC_NUM}"
   declare -gA "$loc"
   declare -g  LOCATION="$loc"

   local -n loc_r="$loc"
   loc_r['start_ln']=
   loc_r['start_col']=
   loc_r['end_ln']=
   loc_r['end_col']=

   local -n file_r="$FILE"
   loc_r['file']="${file_r[path]}"
}


# location:copy()
# @description
#  Copies the properties from `$1`'s location node to `$2`'s. If no properties
#  are specified copy all of them. May only operate on `TOKEN`s and `NODE`s.
#
# @arg   $1    :NODE    Source location-containing node
# @arg   $2    :NODE    Destination location-containing node
function location:copy {
   local -n from_r="$1" ; shift
   local -n to_r="$1"   ; shift
   local -a props=( "$@" )

   local -n from_loc_r="${from_r[location]}"
   local -n to_loc_r="${to_r[location]}"

   if (( ! ${#props[@]} )) ; then
      props=( "${!from_loc_r[@]}" )
   fi

   local k v
   for k in "${props[@]}" ; do
      v="${from_loc_r[$k]}"
      to_loc_r["$k"]="$v"
   done
}


# location:cursor()
# @description
#  Convenience function to create a location at the current cursor's position.
#  Cleans up otherwise messy and repetitive code in the lexer.
#
# @set  LOCATION
# @env  CURSOR
#
# @noargs
function location:cursor {
   location:new
   local -n loc_r="$LOCATION"
   loc_r['start_ln']="${CURSOR[lineno]}"
   loc_r['start_col']="${CURSOR[colno]}"
   loc_r['end_ln']="${CURSOR[lineno]}"
   loc_r['end_col']="${CURSOR[colno]}"

   local -n file_r="$FILE"
   loc_r['file']="${file_r[path]}"
}


# parser:init()
# @description
#  Resets elements of the parser that cannot carry from run to run.
#
# @set   IDX
# @set   TOKEN
# @set   TOKEN_r
# @set   NODE
# @noargs
function parser:init {
   declare -gi IDX=0
   declare -g  TOKEN=''  TOKEN_r=''
   declare -g  NODE=''
}


function parser:advance {
   parser:_advance
   while [[ ${TOKEN_r[type]} == ERROR ]] ; do
      parser:_advance
   done
}

# parser:_advance()
# @internal
# @description
#  Holdover until I wire up synchronization function. Called by parser:advance()
#  to advance current global Token and nameref pointers.
#
# @see   parser:advance
#
# @env   TOKENS
# @env   IDX
# @set   TOKEN
# @set   TOKEN_r
# @noargs
function parser:_advance {
   if (( $IDX < ${#TOKENS[@]} )) ; then
      declare -g  TOKEN="${TOKENS[$IDX]}"
      declare -gn TOKEN_r="$TOKEN"
      (( ++IDX ))
   fi
}


function parser:check {
   # Is $TOKEN_r one of a comma-delimited list of types.
   [[ ,"$1", ==  *,${TOKEN_r[type]},* ]]
}


function parser:match {
   if parser:check "$1" ; then
      parser:advance
      return 0
   fi
   return 1
}


function parser:munch {
   if parser:check "$1" ; then
      parser:advance
   else
      e=( --anchor "$ANCHOR"
          --caught "${TOKEN_r[location]}"
          "${1,,}"  "${TOKEN_r[type],,}"  "$2"
      ); raise munch_error "${e[@]}"
   fi
}


function parser:parse {
   parser:advance
   parser:program
}

#===============================================================================
# @section                     Grammar functions
#-------------------------------------------------------------------------------

# parser:program()
# @description
#  program  -> header container EOF
#
# @env   NODE
# @set   NODE
# @noargs
function parser:program {
   parser:header
   local header="$NODE"

   parser:container
   local container="$NODE"

   ast:new program
   local program="$NODE"
   local -n program_r="$program"
   program_r['header']="$header"
   program_r['container']="$container"
   parser:munch 'EOF'

   declare -g NODE="$program"
}


# parser:header()
# @description
#  header  -> (import | typedef)*
#
# @see   parser:import
# @see   parser:typedef
#
# @env   NODE
# @set   NODE
# @set   ANCHOR
# @noargs
function parser:header {
   ast:new header
   local node="$NODE"
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   while parser:check 'IMPORT,TYPEDEF' ; do
      declare -g ANCHOR="${TOKEN_r[location]}"
      local open="$TOKEN"

      if parser:match 'IMPORT' ; then
         parser:import "$open"
      elif parser:match 'TYPEDEF' ; then
         parser:typedef "$open"
      fi

      items_r+=( "$NODE" )
   done

   declare -g NODE="$node"
}


# parser:container()
# @description
#  container  ->  declaration*
#
# @see   parser:declaration
#
# @env   NODE
# @set   NODE
# @noargs
function parser:container {
   ast:new container
   local node="$NODE"
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   while ! parser:check 'EOF' ; do
      parser:declaration
      items_r+=( "$NODE" )
   done

   declare -g NODE="$node"
}


# parser:import()
# @description
#  import  ->  "import"  IDENTIFIER  ";"
#
# @env   NODE
# @env   TOKEN
# @set   NODE
#
# @arg   $1    :LOCATION   Location for `import` keyword
function parser:import {
   local open="$1"

   parser:path "$TOKEN"
   local path="$NODE"
   parser:munch 'PATH'  'expecting import path'

   ast:new import
   local node="$NODE"
   local -n node_r="$node"
   node_r['path']="$path"

   local close="$TOKEN"
   parser:munch 'SEMI' "expecting \`;' after import"

   location:copy "$open"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'
}


# parser:typedef()
# @description
#  typedef  ->  "typedef"  type  (as IDENTIFIER)?  ";"
#  type     ->  IDENTIFIER  ("[" typelist "]")?
#  typelist ->  type ("," type)+
#
# @see parser:type
#
# @env   NODE
# @env   TOKEN
# @set   NODE
#
# @arg   $1    :LOCATION   Location for `import` keyword
function parser:typedef {
   local open="$1"

   parser:type
   local type="$NODE"

   parser:munch 'AS'  'typedefs require `as <name>`'
   parser:identifier "$TOKEN"
   local ident="$NODE"
   parser:munch 'IDENTIFIER'  'expecting typedef name'

   ast:new typedef
   local node="$NODE"
   local -n node_r="$node"
   node_r['type']="$type"
   node_r['name']="$ident"

   local close="$TOKEN"
   parser:munch 'SEMI' "expecting \`;' after import"

   location:copy "$open"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'
}


# parser:declaration()
# @description
#  declaration -> decl_section
#               | decl_variable
#
# @see parser:decl_section
# @see parser:decl_variable
#
# @env   TOKEN
# @env   NODE
# @set   NODE
# @noargs
function parser:declaration {
   if parser:check 'IMPORT,TYPEDEF' ; then
      e=( --anchor "${TOKEN_r[location]}"
          --caught "${TOKEN_r[location]}"
          'import/typedef statements may only occur at the top of a file'
      ); raise parse_error "${e[@]}"
   fi

   parser:identifier "$TOKEN"
   parser:munch 'IDENTIFIER'  "expecting declaration or closing \`}'"

   if parser:match 'L_BRACE' ; then
      parser:decl_section
   else
      parser:decl_variable
   fi
}


# parser:decl_section()
# @description
#  decl_section -> declaration*
#
# @see parser:declaration
#
# @env   NODE
# @env   TOKEN
# @env   ANCHOR
#
# @set   NODE
# @set   ANCHOR
# @noargs
function parser:decl_section {
   local ident="$NODE"
   local anchor="$ANCHOR"
   local -n ident_r="$ident"
   declare -g ANCHOR="${ident_r[location]}"

   ast:new decl_section
   local node="$NODE"
   local -n node_r="$node"
   node_r['name']="$ident"

   local -n items_r="${node_r['items']}"
   while ! parser:check 'R_BRACE' ; do
      parser:declaration
      items_r+=( "$NODE" )
   done

   local close="$TOKEN"
   parser:munch 'R_BRACE' "expecting \`}' after section."

   location:copy "$ident"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


# parser:decl_variable()
# @description
#  decl_variable -> IDENTIFIER ("@" type)?  expression?  ";"
#
# @see   parser:type
# @see   parser:expression
#
# @env   NODE
# @env   TOKEN
# @env   ANCHOR
#
# @set   NODE
# @set   ANCHOR
# @noargs
function parser:decl_variable {
   # Variable declaration must be preceded by an identifier.
   local ident="$NODE"

   local anchor="$ANCHOR"
   local -n ident_r="$ident"
   declare -g ANCHOR="${ident_r[location]}"

   ast:new decl_variable
   local node="$NODE"
   local -n node_r="$node"

   # shellcheck disable=SC2128
   node_r['name']="$ident"

   # Type declaration.
   local open="$TOKEN"
   if parser:match 'AT' ; then
      declare -g ANCHOR="$open"
      parser:type
      node_r['type']="$NODE"
   fi

   # If current token is one that begins an expression, advise they likely
   # indended a colon before it.
   local expr_types=''
   for expr in "${!NUD[@]}" ; do
      expr_types+=",${expr}"
   done

   # Expressions.
   if parser:match 'COLON' ; then
      parser:expression
      node_r['expr']=$NODE
   elif parser:check "$expr_types" ; then
      e=( --anchor "$ANCHOR"
          --caught "${TOKEN_r[location]}"
          "expecting \`:' before expression"
      ); raise parse_error "${e[@]}"
   fi

   local close="$TOKEN"
   parser:munch 'SEMI' "expecting \`;' after declaration"

   location:copy "$ident"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


# parser:type()
# @description
#  type     ->  IDENTIFIER  [ "[" typelist "]" ]?
#  typelist ->  type ("," type)+
#
#  Within the parameters of a type, [...], Type() nodes are assigned as a linked
#  list to the .next slot. The pointer to the parameters themselves is in the
#  .params slot.
#
#  Example:
#  ```python
#  class Type():
#     def __init__(self, kind: str, param: Type, next: Type):
#        self.kind  = kind
#        self.param = param
#        self.next  = next
#  
#  # rec[list[str], int]
#  int  = Type('INT')
#  str  = Type('STR')
#  list = Type('LIST', param: str, next: int)
#  rec  = Type('RECORD', param: list)
#  ```
#
# @see   parser:typelist
#
# @env   NODE
# @env   TOKEN
# @set   NODE
# @noargs
function parser:type {
   parser:identifier "$TOKEN"
   parser:munch 'IDENTIFIER' 'type declarations must be identifiers'
   local ident="$NODE"

   ast:new type
   local node="$NODE"
   local -n node_r="$node"
   node_r['kind']="$ident"

   local anchor="$ANCHOR"
   local open="$TOKEN"

   if parser:match 'L_BRACKET' ; then
      declare -g ANCHOR="$open"
      parser:typelist "$node"
      parser:munch 'R_BRACKET' "type params must close with \`]'."
   fi

   location:copy "$ident"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"   "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


# parser:typelist()
# @description
#  typelist ->  type ("," type)*
#
# @see   parser:type
#
# @env   NODE
# @set   ANCHOR
# @noargs
function parser:typelist {
   local node="$1"
   local -n node_r="$node"
   local -n items_r="${node_r[subtype]}"

   parser:type
   items_r+=( "$NODE" )

   while parser:match 'COMMA' ; do
      parser:type
      items_r+=( "$NODE" )
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
#   [       list index                 7
#   .       member index               9
#           string concatenation       11

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
   [L_BRACKET]='parser:list'
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

   local token="$TOKEN"
   local type="${TOKEN_r[type]}"

   local fn="${NUD[$type]}"
   if [[ ! $fn ]] ; then
      local -n token_r="$token"
      e=( --anchor "$ANCHOR"
          --caught "${token_r[location]}"
          "expecting an expression"
      ); raise parse_error "${e[@]}"
      return
   fi

   parser:advance
   $fn "$token"
   lhs="$NODE"

   while :; do
      op_type=${TOKEN_r[type]}

      #───────────────────────────( postfix )───────────────────────────────────
      lbp=${postfix_binding_power[$op_type]:-0}
      (( rbp = (lbp == 0 ? 0 : lbp+1) )) ||:

      if [[ $lbp -ge $min_bp ]] ; then
         fn="${RID[${TOKEN_r[type]}]}"

         if [[ ! $fn ]] ; then
            e=( --anchor "$ANCHOR"
                --caught "${token_r[location]}"
                "expecting a postfix expression"
            ); raise parse_error "${e[@]}"
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
         e=( --anchor "$ANCHOR"
             --caught "${token_r[location]}"
             "expecting an infix expression"
         ); raise parse_error "${e[@]}"
      fi

      $fn  "$lhs"  "$op_type"  "$rbp"
      lhs="$NODE"
   done

   declare -g NODE=$lhs
}


function parser:grouping {
   local anchor="$ANCHOR"
   local -n paren_r="$1"
   declare -g ANCHOR="${paren_r[location]}"

   parser:expression
   parser:munch 'R_PAREN' "grouping must be closed by \`)'."

   declare -g ANCHOR="$anchor"
}


function parser:unary {
   local prev="$1"
   local -n prev_r="$prev"
   local op="${prev_r[type]}"
   local rbp="${prefix_binding_power[$op]}"

   ast:new unary
   local node="$NODE"
   local -n node_r="$node"

   local anchor="$ANCHOR"
   declare -g ANCHOR="${prev_r[location]}"

   parser:expression "$rbp"

   node_r['op']="$op"
   node_r['right']="$NODE"

   location:copy "$prev"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


# parser:concat()
# @description
#  String interpolation is parsed as a high left-associative infix operator.
#
# @arg   $1    :Expression    LHS expression
# @arg   $2    :str           Concatenation operator
# @arg   $3    :int           Right binding power
function parser:concat {
   local lhs="$1"  _=$2  rbp="$3"
                    # ^-- ignore operator

   local -n node_r="$lhs"
   until [[ ! "${node_r[concat]}" ]] ; do
      local -n node_r="${node_r[concat]}"
   done

   parser:expression "$rbp"
   node_r['concat']="$NODE"

   location:copy "$lhs"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'file'  'end_ln'    'end_col'

   declare -g NODE="$lhs"
}


function parser:typecast {
   local lhs="$1"
   
   local anchor="$ANCHOR"
   local -n lhs_r="$1"
   declare -g ANCHOR="${lhs_r[location]}"

   ast:new typecast
   local node="$NODE"
   local -n node_r="$node"

   parser:type
   node_r['expr']="$lhs"
   node_r['type']="$NODE"

   location:copy "$lhs"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


function parser:index {
   local lhs="$1"  _="$2"
                     # ^-- ignore rbp

   local anchor="$ANCHOR"
   declare -g ANCHOR="${TOKEN_r[location]}"

   parser:advance # past L_BRACKET.

   ast:new index
   local save="$NODE"
   local -n index="$NODE"

   parser:expression
   index['left']="$lhs"
   index['right']="$NODE"

   local close="$TOKEN"
   parser:munch 'R_BRACKET' "index must be closed by \`]'."

   location:copy "$lhs"    "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$save"
}


function parser:member {
   local lhs="$1"  _=$2  rbp="$3"
                    # ^-- ignore `.` operator

   local anchor="$ANCHOR"
   local -n lhs_r="$1"
   declare -g ANCHOR="${lhs_r[location]}"

   ast:new member
   local node="$NODE"
   local -n node_r="$node"

   parser:identifier "$TOKEN"
   parser:munch 'IDENTIFIER'  'member subscription requires an identifier'

   node_r['left']="$lhs"
   node_r['right']="$NODE"

   location:copy "$lhs"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


function parser:list {
   # Opening `[` Token, for LOCATION information.
   local open="$1"
   local -n open_r="$open"

   local anchor="$ANCHOR"
   declare -g ANCHOR="${open_r[location]}"

   ast:new list
   local node="$NODE"
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   until parser:check 'R_BRACKET' ; do
      parser:expression
      items_r+=( "$NODE" )

      parser:check 'R_BRACKET' && break
      parser:munch 'COMMA' "list elements must be separated by \`,'"
   done

   local close="$TOKEN"
   parser:munch 'R_BRACKET' "list must be closed by \`]'."

   location:copy "$open"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


function parser:env_var {
   local -n token_r="$TOKEN"
   parser:advance # past DOLLAR.

   ast:new env_var
   local -n node_r="$NODE"
   node_r['value']="${token_r[value]}"
   node_r['location']="${token_r[location]}"
}


function parser:identifier {
   local -n token_r="$1"

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
