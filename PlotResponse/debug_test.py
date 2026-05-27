import sys
import debugpy

print("before breakpoint")
debugpy.breakpoint()
print("after breakpoint")

print("argv:", sys.argv)
