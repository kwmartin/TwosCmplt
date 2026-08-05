# Power Minimization at the RTL level

This file summarizes the different steps to be used for minimizing power using gated latches.

## Static analysis

First the circuits of all circuits in the tree of the circuit to be power minimized are identified. Each leaf is identified by the circuit indexes leading to the leaf. The indexes are used as the key in the dictionary. The value of the dictionary will include: module for the module type, name for the name of the leaf, nodes, for a list of internal nodes or each circuit, and level for the total number of circuits in the branch.

Secondly, an array list of all flip-flops will be prepared. Each flip-flop will have a key to be used as an index into the first. This second array list, after simulations, will be ordered into two lists based on number of transistions after a simulation. One will be ordered from high to low, the second will be ordered from low to high. The transition number will be the total number of transitions, divided by the total number of clocks in the the simulation.

A static capacitance initialization analysis will be done. This will be make a capacitance table for each leaf circuit in the hierarchy again indexed by circuit indexes. Each circuit will have a property for total power consumed internally and for power consumed externally by drivers at the output ports. The capacitinaces of internal nodes, and the capacitances of external nodes will be set in this phase. It is expected that capacitances might be changed a number of times, and can even be changed dynamically during simulation, Initially, they will set dependent on the input capacitances of the nodeSinks property of the external nodes, and also using a heuristic guess at wiring capacitances based the count of nodeSinks and on the level of the hierarchy with level closer to the head adding additional wiring capacitancs; the amount to be iterated on as better information becomes available.

## Test simulations

A number of different test simulations will be iteratively generated and added to. These simulations will be identified by top level inputs. Many top level inputs will be the same for all all simulations, including VDD, VSS, and INIT. Some top level simulations will change from simulation to simulation, and these will be identified by the a index into the the top level bus. This index will be used to retrieve a list from a dictionary of different [TimeSpec] inputs. This dictionary will also retrieve in addition to a specific [TimeSpec] input, power rating which will correspond to total number of transitions with each transition being multiplied by the capacitance at that node.

## Power Simulations

During simulations, each node change will index into a power dictionary containing indexes for all circuits that will add to the power of that circuit an amount proportional to the nodes capacitance being changed.

## Power Ordering

After a simulation, all the circuits will be ordered from high power to low power. Also, all the flip flops will be ordered from low change density to high change density.

## Flipflop swap

After a simulation, all flip-flops with change densities below a certain threshold will be swapped by "Enable" flip-flops, if they were not already an enable flip-flop and if they have an enable version as ascertained by a "SwapFF" dictionary. Next the same simulation will be re-run, and total power for all the flip-flops will be re-examined. Any flip-flops that did not have a power reduction by at least 30% will be swapped back and marked in the flip-flop dictionary and "NOT_SWAPPABLE"

This process will be repeated for different sets of inputs that generated the largest amount of power for a specified number of simulations.
