#!/bin/bash
# Establishing truth table for SET vs. UNSET, and EMPTY vs. NON-EMPTY.

# Set, empty.
declare -- se=

# Set, non-empty.
declare -- ne='set'

# Non-set
#declare -- ns

#    TEST                          #      SET      VALUE     RESULT   
#---------------------------------------------------------------------
[[ ${ne}     ]] && echo  "ne"      #      YES       YES      TRUE
[[ ${se}     ]] && echo  "se"      #      YES        NO      FALSE
[[ ${ns}     ]] && echo  "ns"      #       NO       ---      FALSE

[[ ${ne-_}   ]] && echo  "ne-_"    #      YES       YES      TRUE
[[ ${se-_}   ]] && echo  "se-_"    #      YES        NO      FALSE
[[ ${ns-_}   ]] && echo  "ns-_"    #       NO       ---      TRUE

[[ ${ne:-_}  ]] && echo  "ne:-_"   #      YES       YES      TRUE
[[ ${se:-_}  ]] && echo  "se:-_"   #      YES        NO      TRUE
[[ ${ns:-_}  ]] && echo  "ns:-_"   #       NO       ---      TRUE

[[ ${ne+_}   ]] && echo  "ne+_"    #      YES       YES      TRUE
[[ ${se+_}   ]] && echo  "se+_"    #      YES        NO      TRUE
[[ ${ns+_}   ]] && echo  "ns+_"    #       NO       ---      FALSE

[[ ${ne:+_}  ]] && echo  "ne:+_"   #      YES       YES      TRUE
[[ ${se:+_}  ]] && echo  "se:+_"   #      YES        NO      FALSE
[[ ${ns:+_}  ]] && echo  "ns:+_"   #       NO       ---      FALSE

# TO USE...
# Find a section in which the desired value has a unique result. E.g., where
# the result of ${ns...} is not the same as the result of `ne` or `se`.

# Results...
#  UNSET              [[ ! ${var+_} ]]
#  SET AND EMPTY      [[ ! ${var-_} ]]
#  SET AND NONEMPTY   [[   ${var}   ]]
