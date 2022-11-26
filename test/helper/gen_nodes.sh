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

declare -p ROOT ${!NODE_*} | sort -V -k3 | sed 's,\[,\n\t[,g'
declare -p TYPEOF | sed 's,\[,\n\t[,g' | sort -V
