#!/bin/bash
#
# There are two primary concerns with a bash-based configuration language.
#  1. Time to access
#  2. Time to validate
#
# The former deals with the overhead added both in script complexity, as well as
# computation time, to access values from the config file.
#
# The latter is addressed here. Validation will add some static chunk of startup
# time to the application. It scales with the number of validation steps, raerpb
# the number of invocations in the calling script (as in pt. 1).

# The opcodes here will probably be pretty different from a traditional VM, as
# we only care about operations involving comparisons, and path manipulation.
# Support for date objects makes logical sense as the next thing to add. As I
# see it, configuration files require:
#  1. Integers
#  2. Strings
#  3. Arrays
#  4. Maps
#  5. Paths
#  6. Dates
# Native datetime & path support is missing from almost every file format (json,
# yaml, cfg, etc.).

# TODO:
# Probs going to need to wrap the shit on the stack with a "Value" type, sorta
# like what I've done in `tasha`.
#> class Value:
#>    type  : type_t              # enum of internal types
#>    value : str

#declare -i NUM_OPS="${#OP_CODES[@]}"
#while [[ $IP -lt $NUM_OPS ]] ; do
#   declare -n op=${OP_CODES[IP]}
#
#   case "${op[code]}" in
#   esac
#
#   (( ++IP ))
#done


# THINKIES:
# What tests/directives do I need, and how will they work? Certainly path-
# related things.
#  - exists
#  - writable
#  - readable
#  - executable

: "
   TYPE           CODE        ARG1        ARG2       ARG3        META
   ---------------------------------------------------------------------------
   file/dir       EXIST       file                       
                  READ        file                       
                  WRITE       file                       
                  EXECUTE     file                       
                  CHMOD       file        attr
                  CHOWN       file        user       group

   functions      LOAD_FN     fn_base_name
                  EXE_TEST
                  EXE_DRV
  "

# For builtin tests/directives, we can have op codes specifically for their
# functionality. E.g., `exists`, `readable`. For all else, they'll need to
# be loaded as functions.
#
# LOAD_FN adds the `base' name of a function onto the stack. EXE_TEST will pop
# pop the base name, prefix it with `test_`, and execute the function body.
# While EXE_DRV will pop the base name, first evaluate if the `test_` is true,
# then run the `directive_` if not.

# THINKIES:
#  1. Need expressions (test context):
#     - "Is this writable", "am I the owner of the file"?
#  2. Need statements (directive context):
#     - External side effects
#       - Make this file writable
#       - `chown` this file
#     - Internal side effects
#       - Modify the value of a config variable itself: make something upper
#         case, set the abs() of a number, make a number 0 if set <0.
#
# I like having these structured as directives/tests, rather than inline
# expressions, as it enforces legibility where it counts--in the config file.
# The logic is in library code, and the function names should hopefully be
# descriptive enough to inform the user what the context steps do.
