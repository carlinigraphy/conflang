#!/bin/bash
#
# Writing tests requires having known-good output to compare to. This is how we
# get that output more easily.

declare -g  PROGDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" ; pwd )
declare -g  LIBDIR="${PROGDIR}"/../../lib

source "${LIBDIR}"/../bin/confc
source "${LIBDIR}"/files.sh
source "${LIBDIR}"/errors.sh
source "${LIBDIR}"/lexer.sh

globals:init
lexer:init
lexer:scan

declare -p TOKENS ${!TOKEN_*} | sort -V -k3
