#!/bin/bash
#
# Writing tests requires having known-good output to compare to. This is how we
# get that output more easily.

declare -g  PROGDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" ; pwd )
declare -g  LIBDIR="${PROGDIR}"/../../lib

declare -a  INCLUDE_ROOT=()
declare -ga FILES=( "${1?}" )

source "${LIBDIR}"/utils.sh
source "${LIBDIR}"/errors.sh
source "${LIBDIR}"/lexer.sh
source "${LIBDIR}"/parser.sh
lexer:init
lexer:scan
parser:init
parser:parse

for n in ${!NODE_*} ; do
   t="${TYPEOF[$n]}"
   [[ "$t" ]] && printf "\n$t\n"
   declare -p "$n" | sed -e 's,declare\s-[-Aa]\s,,g' -e 's,\[,\n\t[,g'
done
