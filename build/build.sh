#!/usr/bin/env bash

dst="${1:-/dev/stdout}"

PROGDIR=$( cd $(dirname "${BASH_SOURCE[0]}") ; pwd )
LIBDIR="${PROGDIR}"/../lib/

awk -f "${PROGDIR}"/prebuild.awk "${LIBDIR}"/*.sh > "$dst"
