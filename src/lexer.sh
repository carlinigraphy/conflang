#!/bin/bash
#===============================================================================
# @section                        Lexer utils
#-------------------------------------------------------------------------------

declare -gA KEYWORD=(
   ['true']=true
   ['false']=true
   ['import']=true
   ['as']=true
   ['typedef']=true
)

# lexer:init()
# @description
#  Resets global variables that are specific to *only* this run of the lexer.
#  Some information (e.g., `_TOKEN_NUM`) helps to not reset. Allows for easier
#  debugging if it's not constantly stomped by each successive run.
#
function lexer:init {
   local -n file_r="$FILE"
   declare -g   FILE_LINES="${file_r[lines]}"
   declare -g   CHAR=''  PEEK_CHAR=''
   declare -ga  CHARRAY=()
   declare -ga  TOKENS=()
   declare -gA  FREEZE CURSOR=(
      [index]=-1
      [lineno]=1
      [colno]=0
   )
}

# token:new()
# @description
#  Creates new Token object, appending to `TOKENS[]`. Store location information
#  via frozen start line/col, and ending line/col.
#
# @env   LOCATION
# @set   TOKENS[]
# @set   TOKEN
# @arg   $1    :str   Type of Token (`INTEGER`, `STRING`, ...)
# @arg   $2    :str   Value of Token (character, string, identifier, ...)
function token:new {
   local type=$1  value=$2

   local token="TOKEN_$(( ++_TOKEN_NUM ))"
   declare -gA "$token"
   TOKENS+=( "$token" )

   # Nameref to newly created global token.
   declare -n t_r="$token"

   # Token data.
   t_r['type']="$type"
   t_r['value']="$value"

   location:new
   t_r['location']="$LOCATION"

   local -n loc_r="$LOCATION"
   loc_r['start_ln']="${FREEZE[lineno]}"
   loc_r['start_col']="${FREEZE[colno]}"
   loc_r['end_ln']="${CURSOR[lineno]}"
   loc_r['end_col']="${CURSOR[colno]}"

   local -n file_r="$FILE"
   loc_r['file']="${file_r[path]}"
}


#===============================================================================
# @section                           Lexer
#-------------------------------------------------------------------------------

function lexer:scan {
   local -n file_r="$FILE"

   # Fastest method to read a file into a string. Beats `read -d ''` and `cat`
   # by 2.5 to 3x.
   local input=$( <"${file_r[path]}" )

   # For easier lookahead, read all characters first into an array. Allow easy
   # seek/index.
   local char
   while read -rN1 char ; do
      CHARRAY+=( "$char" )
   done <<< "$input"

   # For later error reporting. Easier to report errors by line number if we
   # have them in lines... by number...
   local -n file_lines_r="$FILE_LINES"
   readarray -t -O1 file_lines_r <<< "$input"

   while (( "${CURSOR[index]}" < ${#CHARRAY[@]} )) ; do
      lexer:advance ; [[ ! "$CHAR" ]] && break

      # Save current cursor information.
      FREEZE['index']=${CURSOR['index']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      # Skip comments.
      if [[ $CHAR == '#' ]] ; then
         lexer:comment ; continue
      fi

      # Skip whitespace.
      if [[ $CHAR =~ [[:space:]] ]] ; then
         continue
      fi

      # Symbols.
      case $CHAR in
         '@')  token:new  'AT'        "$CHAR"  ; continue ;;
         '.')  token:new  'DOT'       "$CHAR"  ; continue ;;
         ',')  token:new  'COMMA'     "$CHAR"  ; continue ;;
         ';')  token:new  'SEMI'      "$CHAR"  ; continue ;;
         ':')  token:new  'COLON'     "$CHAR"  ; continue ;;
         '$')  token:new  'DOLLAR'    "$CHAR"  ; continue ;;
         '?')  token:new  'QUESTION'  "$CHAR"  ; continue ;;
                                      
         '(')  token:new  'L_PAREN'   "$CHAR"  ; continue ;;
         ')')  token:new  'R_PAREN'   "$CHAR"  ; continue ;;

         '[')  token:new  'L_BRACKET' "$CHAR"  ; continue ;;
         ']')  token:new  'R_BRACKET' "$CHAR"  ; continue ;;

         '{')  token:new  'L_BRACE'   "$CHAR"  ; continue ;;
         '}')  token:new  'R_BRACE'   "$CHAR"  ; continue ;;
      esac

      # Typecast, or minus.
      if [[ $CHAR == '-' ]] ; then
         # If subsequent `>', is an arrow for typecast.
         if [[ $PEEK_CHAR == '>' ]] ; then
            lexer:advance
            token:new 'ARROW' '->'
         else
            token:new 'MINUS' '-'
         fi

         continue
      fi

      # f-{strings,paths}
      if [[ $CHAR == 'f' ]] ; then
         if   [[ $PEEK_CHAR == '"' ]] ; then
            lexer:advance ; lexer:fstring
            continue
         elif [[ $PEEK_CHAR == "'" ]] ; then
            lexer:advance ; lexer:fpath
            continue
         fi
      fi

      # Identifiers.
      if [[ $CHAR =~ [[:alpha:]_] ]] ; then
         lexer:identifier ; continue
      fi

      # Strings. Surrounded by `"`.
      if [[ $CHAR == '"' ]] ; then
         lexer:string ; continue
      fi

      # Paths. Surrounded by `'`.
      if [[ $CHAR == "'" ]] ; then
         lexer:path ; continue
      fi

      # Numbers.
      if [[ $CHAR =~ [[:digit:]] ]] ; then
         # Bash only natively handles integers. It's not able to do floats
         # without bringing `bc` or something. For now, that's all we'll also
         # support. Maybe later I'll add a float type, just so I can write some
         # external functions that support float comparisons. Or maybe you just
         # accept that you're taking a performance hit by using floats. More
         # subshells and whatnot.
         lexer:number ; continue
      fi

      token:new 'ERROR'
      local -n t_r="${TOKENS[-1]}"
      e=( --anchor "${t_r[location]}"
          --caught "${t_r[location]}"
          "invalid character [$CHAR]"
      ); raise syntax_error "${e[@]}"
   done

   FREEZE[lineno]="${CURSOR[lineno]}"
   FREEZE[colno]="${CURSOR[colno]}"
   token:new 'EOF'
}


# lexer:advance()
# @description
#  Advances cursor position in file. Sets global vars for the current and next
#  characters.
#  
# @env   CURSOR
# @env   CHARRAY
# @set   CHAR
# @set   PEEK_CHAR
# @noargs
function lexer:advance {
   (( ++CURSOR['colno'] )) ||:
   (( ++CURSOR['index'] )) ||:
   local -i idx="${CURSOR[index]}"

   declare -g CHAR="${CHARRAY[$idx]}"
   declare -g PEEK_CHAR="${CHARRAY[$idx + 1]}"

   if [[ "$CHAR" == $'\n' ]] ; then
      (( ++CURSOR['lineno'] ))
      CURSOR['colno']=0
   fi
}


function lexer:comment {
   # There are no multiline comments. Seeks from '#' to the end of the line.
   while [[ -n $CHAR ]] ; do
      [[ "$PEEK_CHAR" =~ $'\n' ]] && break
      lexer:advance
   done
}


function lexer:identifier {
   local buffer="$CHAR"

   while [[ -n $CHAR ]] ; do
      [[ $PEEK_CHAR =~ [^[:alnum:]_] ]] && break
      lexer:advance ; buffer+="$CHAR"
   done

   if [[ ${KEYWORD[$buffer]} ]] ; then
      token:new "${buffer^^}" "$buffer"
   else
      token:new 'IDENTIFIER' "$buffer"
   fi
}


function lexer:string {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == '"' ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset 'buffer[-1]'
         else
            break
         fi
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   token:new 'STRING' "$join"

   # This comes after the token creation above, as it contains the cursor
   # information for the initial quote character.
   if [[ ! $PEEK_CHAR ]] ; then
      local anchor="$LOCATION"
      location:cursor
      e=( --anchor "$anchor"
          --caught "$LOCATION"
          "unterminated string"
      ); raise unterminated_string "${e[@]}"
   fi
}


function lexer:path {
   local -a buffer=()

   local -n t_r="${TOKENS[-1]}"
   local anchor="${t_r[location]}"

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == "'" ]] ; then
         # shellcheck disable=SC1003
         # Misidentified error.
         if [[ $buffer && ${buffer[-1]} == '\' ]] ; then
            # shellcheck disable=SC2184
            unset 'buffer[-1]'
         else
            break
         fi
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   # Create token.
   token:new 'PATH' "$join"

   # This comes after the token creation above, as it contains the cursor
   # information for the initial quote character.
   if [[ ! $PEEK_CHAR ]] ; then
      local anchor="$LOCATION"
      location:cursor
      e=( --anchor "$anchor"
          --caught "$LOCATION"
          "unterminated path"
      ); raise unterminated_string "${e[@]}"
   fi
}


function lexer:number {
   local number="${CHAR}"
   while [[ $PEEK_CHAR =~ [[:digit:]] ]] ; do
      lexer:advance ; number+="$CHAR"
   done
   token:new 'INTEGER' "$number"
}


function lexer:interpolation {
   location:cursor
   local anchor="$LOCATION"

   while [[ "${CURSOR[index]}" -lt ${#CHARRAY[@]} ]] ; do
      # String interpolation ends upon a closing R_BRACE token, or if there's
      # no current character.
      if [[ ! $CHAR ]] || [[ $PEEK_CHAR == '}' ]] ; then
         break
      fi

      lexer:advance

      # Skip whitespace.
      if [[ $CHAR =~ [[:space:]] ]] ; then
         continue
      fi

      # Save current cursor information.
      FREEZE['index']=${CURSOR['index']}
      FREEZE['lineno']=${CURSOR['lineno']}
      FREEZE['colno']=${CURSOR['colno']}

      case $CHAR in
         '.')  token:new        'DOT' "$CHAR"  ; continue ;;
         '$')  token:new     'DOLLAR' "$CHAR"  ; continue ;;
         '[')  token:new  'L_BRACKET' "$CHAR"  ; continue ;;
         ']')  token:new  'R_BRACKET' "$CHAR"  ; continue ;;
      esac

      # Identifiers.
      if [[ $CHAR =~ [[:alpha:]_] ]] ; then
         lexer:identifier ; continue
      fi

      token:new 'ERROR'
      local -n t_r="${TOKENS[-1]}"
      e=( --anchor "$anchor"
          --caught "${t_r[location]}"
          "invalid character in fstring [$CHAR]"
      ); raise invalid_interpolation_char "${e[@]}"
   done
}


function lexer:fstring {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == '"' ]] ; then
         # shellcheck disable=SC1003
         if [[ $buffer && ("${buffer[-1]}" == '\') ]] ; then
            unset 'buffer[-1]'
         else
            break
         fi
      fi

      # When used outside an expression, closing braces must be escaped.
      if [[ $CHAR == '}' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset 'buffer[-1]'
            buffer+=( "$CHAR" )
            continue
         else
            token:new 'ERROR'
            local -n t_r="${TOKENS[-1]}"
            location:cursor
            e=( --anchor "${t_r[location]}"
                --caught "$LOCATION"
            ); raise unescaped_interpolation_brace "${e[@]}"
         fi
      fi

      # Start of f-string.
      if [[ $CHAR == '{' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset 'buffer[-1]'
            buffer+=( "$CHAR" )
            continue
         fi

         # When beginning f-expressions, create a STRING token for all the text
         # found prior and reset the string buffer.
         local join=''
         for c in "${buffer[@]}" ; do
            join+="$c"
         done
         buffer=()

         token:new 'STRING'  "$join"
         token:new 'CONCAT'

         # In the case of an empty expression...
         #> _: f'{}';
         #...there will be two subsequent concat tokens, with nothing between.
         #> path('') CAT CAT path('')
         #>             ^-- expr would go here.
         #
         # In that case we want to only add one concatenation token before, and
         # omit the closing one.
         local t0="$_TOKEN_NUM"

         lexer:interpolation
         lexer:advance # past the closing `}'

         # Only create the closing CONCAT token if there were contents to the
         # expression.
         local t1="$_TOKEN_NUM"
         if (( t0 != t1 )) ; then
            token:new 'CONCAT'
         fi

         continue
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   token:new 'STRING' "$join"
}


function lexer:fpath {
   local -a buffer=()

   while [[ $PEEK_CHAR ]] ; do
      lexer:advance

      if [[ $CHAR == "'" ]] ; then
         # shellcheck disable=SC1003
         if [[ $buffer && ("${buffer[-1]}" == '\') ]] ; then
            unset 'buffer[-1]'
         else
            break
         fi
      fi

      # When used outside an expression, closing braces must be escaped.
      if [[ $CHAR == '}' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset 'buffer[-1]'
            buffer+=( "$CHAR" )
            continue
         else
            token:new 'ERROR'
            local -n t_r="${TOKENS[-1]}"
            location:cursor
            e=( --anchor "${t_r[location]}"
                --caught "$LOCATION"
            ); raise unescaped_interpolation_brace "${e[@]}"
         fi
      fi

      # Start of f-path.
      if [[ $CHAR == '{' ]] ; then
         if [[ $buffer && "${buffer[-1]}" == '\' ]] ; then
            unset 'buffer[-1]'
            buffer+=( "$CHAR" )
            continue
         fi

         # When beginning f-expressions, create a PATH token for all the text
         # found prior and reset the string buffer.
         local join=''
         for c in "${buffer[@]}" ; do
            join+="$c"
         done
         buffer=()

         token:new 'PATH'  "$join"
         token:new 'CONCAT'

         # In the case of an empty expression...
         #> _: f'{}';
         #...there will be two subsequent concat tokens, with nothing between.
         #> path('') CAT CAT path('')
         #>             ^-- expr would go here.
         #
         # In that case we want to only add one concatenation token before, and
         # omit the closing one.
         local t0="$_TOKEN_NUM"

         lexer:interpolation
         lexer:advance # past the closing `}'

         # Only create the closing CONCAT token if there were contents to the
         # expression.
         local t1="$_TOKEN_NUM"
         if (( t0 != t1 )) ; then
            token:new 'CONCAT'
         fi

         continue
      fi

      buffer+=( "$CHAR" )
   done

   local join=''
   for c in "${buffer[@]}" ; do
      join+="$c"
   done

   token:new 'PATH' "$join"
}
