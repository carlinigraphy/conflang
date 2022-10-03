#!/bin/bash
#
# Starting to think about how to structure the VM. I think "native" functions
# should be compiled as a series of op codes. The ffi can load singular bash
# functions.
#
# Compiled tests/directives.
# Array of super simple op codes, though for things that would be useful for
# comparisons & doing directive-y things. Example for `exists-test`.
#
# Value(
#     type:    Function
#     subtype: Native
#     code: [
#        DIRECTORY,
#        STORE_TYPE
#        FETCH_VALUE,
#        EQUALS,
#     ]
# )
#
# And a FFI test
# Value(
#     type:    Function
#     subtype: Foreign
#     code:    $fn_hash
# )
#
# It may help to completely ignore the FFI for now. What functionality (and
# more specifically OP codes) would be useful for some native functions?
#
# Comparisons.
#  LT
#  GT
#  EQ
#
# Logical operations.
#  NOT
#  OR
#  AND
#
# File specific.
#  IS_FILE
#  IS_DIR
#  IS_READ
#  IS_WRITE
#  IS_EXEC
#  MK_FILE
#  MK_DIR
#  MK_READ
#  MK_WRITE
#  MK_EXEC
