#!/bin/bash

declare -gi NODE_NUM=0
declare -gA TYPEOF=()

# Wrapper around the below functions. Just for convenience. Little easier to
# read as well perhaps.
function ast:new { _ast_new_"$1" ;}


function _ast_new_program {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$NODE"
   node_r['header']=
   node_r['container']=
}


function _ast_new_header {
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   (( ++NODE_NUM ))
   local items="NODE_${NODE_NUM}"
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
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

   local -n node_r="$node"
   node_r['path']=''
   node_r['as']=''

   location:new
   node_r['location']="$LOCATION"
}


function _ast_new_container {
   ast:new identifier                  # name:  %container
   local ident="$NODE"
   local -n ident_r="$ident"
   ident_r['value']='%container'

   location:new
   local -n loc_r="$LOCATION"          #--^ name's location info
   loc_r['file']="$FILE_IDX"
   loc_r['start_ln']=1
   loc_r['start_col']=1
   loc_r['end_ln']=1
   loc_r['end_col']=1

   ast:new decl_section                # section:  %container
   declare -g ROOT="$NODE"
   local node="$NODE"
   local -n node_r="$node"
   node_r['name']="$ident"

   location:new                        #--^ section's location info
   local -n loc_r="$LOCATION"
   loc_r['start_ln']=1
   loc_r['start_col']=1
   loc_r['file']="$FILE_IDX"
}


function _ast_new_decl_section {
   # 1) create section container
   (( ++NODE_NUM ))
   local node="NODE_${NODE_NUM}"
   declare -gA "$node"
   declare -g NODE="$node"

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
   node_r['kind']=''
   node_r['params']=''
   node_r['next']=''

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


#──────────────────────────────────( utils )────────────────────────────────────
function parser:init {
   declare -gi IDX=0
   declare -g  TOKEN_r=''  TOKEN=''
   # Calls to `advance' both globally set the name of the current/next node(s),
   # e.g., `TOKEN_1', as well as declaring a nameref to the variable itself.

   declare -g  ROOT=''        #< Root of this tree
   declare -g  NODE=''        #< Last generated AST node
}


function parser:_advance {
   if (( $IDX < ${#TOKENS[@]} )) ; then
      declare -g  TOKEN="${TOKENS[$IDX]}"
      declare -gn TOKEN_r="$TOKEN"
      (( ++IDX ))
   fi
}


function parser:advance {
   parser:_advance
   while [[ ${TOKEN_r[type]} == ERROR ]] ; do
      parser:_advance
   done
}


function parser:synchronize {
   until parser:check 'SEMI,EOF' ; do
      parser:advance
   done
   declare -g PANICKING=
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
      e=( munch_error
         --anchor "$ANCHOR"
         --caught "${TOKEN_r[location]}"
         "${1,,}"  "${TOKEN_r[type],,}"  "$2"
      ); raise "${e[@]}"
   fi
}


function parser:parse {
   parser:advance
   parser:program
}

#────────────────────────────( grammar functions )──────────────────────────────
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
}


function parser:header {
   ast:new header
   local node="$NODE"
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   declare -g ANCHOR="${TOKEN_r[location]}"
   while parser:match 'IMPORT' ; do
      parser:import
      items_r+=( "$NODE" )
   done

   declare -g NODE="$node"
}


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


function parser:import {
   parser:path "$TOKEN"
   local path="$NODE"
   parser:munch 'PATH'  'expecting import path'

   parser:munch 'AS'  'imports require `as <name>`'

   parser:identifier "$TOKEN"
   local ident="$NODE"
   parser:munch 'IDENTIFIER'  'expecting import name'

   ast:new import
   local node="$NODE"
   local -n node_r="$node"
   node_r['path']="$path"
   node_r['name']="$ident"

   parser:munch 'SEMI' "expecting \`;' after import"
}


function parser:declaration {
   parser:identifier "$TOKEN"
   parser:munch 'IDENTIFIER'  "expecting declaration or closing \`}'"

   if parser:match 'L_BRACE' ; then
      parser:decl_section
   else
      parser:decl_variable
   fi
}


function parser:decl_section {
   local ident="$NODE"
   local sect="$SECTION"

   local anchor="$ANCHOR"
   local -n ident_r="$ident"
   declare -g ANCHOR="${ident_r[location]}"

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

   local close="$TOKEN"
   parser:munch 'R_BRACE' "expecting \`}' after section."

   location:copy "$ident"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
   declare -g SECTION="$sect"
}


function parser:decl_variable {
   # Variable declaration must be preceded by an identifier.
   local ident="$NODE"

   local anchor="$ANCHOR"
   local -n ident_r="$ident"
   declare -g ANCHOR="${ident_r[location]}"

   ast:new decl_variable
   local node="$NODE"
   local -n node_r="$node"

   #  ┌── incorrectly identified error by `shellcheck`.
   # shellcheck disable=SC2128
   node_r['name']="$ident"

   # Typedefs.
   local open="${TOKEN_r[location]}"
   if parser:match 'AT' ; then
      declare -g ANCHOR="$open"
      parser:typedef
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
      e=( parse_error
         --anchor "$ANCHOR"
         --caught "${TOKEN_r[location]}"
         "expecting \`:' before expression"
      ); raise "${e[@]}"
   fi

   local close="$TOKEN"
   parser:munch 'SEMI' "expecting \`;' after declaration"

   location:copy "$ident"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$close"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}

# parser:typedef()
#
# @description
#  As records and lists may take parameters (`@rec[str, int]`), this function
#  creates a linked list in the .params slot. Each type within .params sets
#  the .next slot.
#
function parser:typedef {
   parser:identifier "$TOKEN"
   parser:munch 'IDENTIFIER' 'type declarations must be identifiers'
   local ident="$NODE"

   ast:new typedef
   local node="$NODE"
   local -n node_r="$node"
   node_r['kind']="$ident"

   local anchor="$ANCHOR"
   local open="${TOKEN_r[location]}"

   if parser:match 'L_BRACKET' ; then
      declare -g ANCHOR="$open"

      parser:typelist
      node_r['params']="$NODE"

      parser:munch 'R_BRACKET' "type params must close with \`]'."
   fi

   location:copy "$ident"  "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"   "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


# @arg $1 NODE  The parent AST node
function parser:typelist {
   parser:typedef
   local node="$NODE"
   local -n node_r="$node"

   while parser:match 'COMMA' ; do
      parser:typedef
      node_r['next']="$NODE"
      local -n node_r="$NODE"
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

   local token="$TOKEN"
   local type="${TOKEN_r[type]}"

   local fn="${NUD[$type]}"
   if [[ ! $fn ]] ; then
      local -n token_r="$token"
      e=( parse_error
         --anchor "$ANCHOR"
         --caught "${token_r[location]}"
         "expecting an expression"
      ); raise "${e[@]}"
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
            e=( parse_error
               --anchor "$ANCHOR"
               --caught "${token_r[location]}"
               "expecting a postfix expression"
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
            --anchor "$ANCHOR"
            --caught "${token_r[location]}"
            "expecting an infix expression"
         ); raise "${e[@]}"
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

   location:copy "$prev"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"   "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
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
   node_r['concat']="$NODE"

   location:copy "$lhs"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'file'  'end_ln'    'end_col'

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
   
   local anchor="$ANCHOR"
   local -n lhs_r="$1"
   declare -g ANCHOR="${lhs_r[location]}"

   ast:new typecast
   local node="$NODE"
   local -n node_r="$node"

   parser:typedef
   node_r['expr']="$lhs"
   node_r['typedef']="$NODE"

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
   parser:munch 'IDENTIFIER'  'member subscription requires an identifer'

   node_r['left']="$lhs"
   node_r['right']="$NODE"

   location:copy "$lhs"   "$node"  'file'  'start_ln'  'start_col'
   location:copy "$NODE"  "$node"  'file'  'end_ln'    'end_col'

   declare -g ANCHOR="$anchor"
   declare -g NODE="$node"
}


function parser:array {
   # Opening `[` Token, for LOCATION informatino.
   local open="$1"
   local -n open_r="$open"

   local anchor="$ANCHOR"
   declare -g ANCHOR="${open_r[location]}"

   ast:new array
   local node="$NODE"
   local -n node_r="$node"
   local -n items_r="${node_r[items]}"

   until parser:check 'R_BRACKET' ; do
      parser:expression
      items_r+=( "$NODE" )

      parser:check 'R_BRACKET' && break
      parser:munch 'COMMA' "array elements must be separated by \`,'"
   done

   local close="$TOKEN"
   parser:munch 'R_BRACKET' "array must be closed by \`]'."

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
