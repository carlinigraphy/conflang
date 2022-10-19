#!/usr/bin/env python3

#a = []          # 0
#b = ['a', 'c']  #   2
#c = ['d']       #  1
#d = []          # 0

a = []           # 0
b = ['a', 'c']   #    3
c = ['d', 'e']   #   2
d = []           # 0
e = ['f']        #  1
f = []           # 0

def get_depth(node, level=0):
    if len(node) == 0:
        return level

    levels = []
    for n in node:
        levels.append(get_depth(eval(n), level+1))

    max = levels[0]
    for i in levels:
        if i > max:
            max = i

    return max

print('a', get_depth(a))
print('b', get_depth(b))
print('c', get_depth(c))
print('d', get_depth(d))
print('e', get_depth(e))
print('f', get_depth(f))
