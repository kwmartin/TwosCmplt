## ClaudeInstructions.md

We have to fix how slices are handled at both circuit parsing and at simulation. This will be done in a number of steps.

First, the parsing of verilog assignment statements will be reviewed, understood, and described in a detailed CircDef.md file. The more detail included, the better. particular detail will be used to describe how the right-hand-side (rhs) of assignment statements is parsed and determined. Currently, I think there might be some errors in how this is done using the CircDef.eprs which are indexes to CircDef.stmts which contains [StmntAST]. In particular, two relevant enums are assgnst and concatst. I'm not sure why they both exist, and if this is not necessary, they should be consolidated into one. In addition, the current approach to using CirDef.exprs and CircDev.stmts will be investigated. For example, at a breakpoint at CircParse.swift:1564, I see many entries in self.exprs but no entries in self.stmts, and most of the entries in self.exprs are select enums for ADDR1R_ which I think is equivalent to a slice. Also, in CircuitParse.swift, the structs: AssgnAST and SingleConcatAST appear to be identical. This should not be necessary. Are they both being used, and if so how?

Secondly, the algorithms for converting verilog assignment statements will described in CircDef.md.

The initial proposed algorithm is:

1) Each assignment statement is realized in a Circuit using a concat gate.
2) Each concat gate has a single output multiple-bit output port.
3) The output of a concat gate goes to a simple node connected directly to one or more component input ports.
4) The input porst of concat gates come from .slice nodes, each input port comes from one .slice node.
5) The sum of the bit counts of all the .slice nodes must be equal to the bit count of the .simple node connected to the concat output.
6) Each concat is an async gate and is included in the sorting and must end in the evalOrder queue.

This algorithm will be reviewed and evaluated for correctness. It will also be compared to other popular algorithms.

The first step of refactoring will be fix the parsing and to add .slice nodes for each slice or equivalently select. These slices will then be used as inputs to concat gates. We need to decide if every slice goes only to an input port of a concat gate? I think this should be the case.

The second step will be to fix Gate.swift to properly handle concat gates. It think this is currently being done using .join at line 158. In Gate.swift, there is also the function busConcat(); are both of these mechanisms being used? Can they be consolidated? In TwosCmplt/Resources/LogicLib are the files Join.yml, Join3.yml, Join4.yml, Concat.yml and Concat4.yml. All of these are for a specific number of bits. I'm guessing they should all be removed, and that concat gates should be handled in Gate.swift for an arbitrary number of bits in a similar mannet to how regs are handled? We need to clean up and consolidate how to concatenate slices. This needs to include how we handle enum Buss and BussArray which is an aliase for [Buss].

