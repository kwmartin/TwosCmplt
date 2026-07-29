# Simulation.md

This file is a  condensed description of our Simulation algorithm

## Architecture

- **Circuits** — Circuits have components with inputs and output; we have decided not to support inouts as we want signal flow to be directed from inputs to outputs.

- **Components** - must be either gates or Circuits. Circuits can be either subcirc or verilog. Gates can be either async or sync. If a Circuit is verilog, its component Circuits must also contain only Verilog structures or Verilog instantiations. An async gate must be evaluated whenever its inputs change, and its output changed deterministically some delay time later. A sync gate is only evaluated on a specified edge of specified signals. This is most commonly called CLK, but there may also be asynchronous inputs for immediate setting and resetting. A Circuit of type subcirc can be either synchronous or asynchronous; examples are state machines and multi-bit adders with registers. All input ports and output ports of both gates and Circuits are considered multi-bit. When a gate output is described by a single name, it is considered to be a 1-bit outport port.

- **Nodes** - are always multi-bit, with a one-bit node (which is very common) being a special case. Each node can only have one driver, but can have many sinks that it affects. Most nodes are are of kind .simple which means they are driven by all the bits of an output port. Whenever a slice is used as part of a concatenated input, it will have its own node with kind .slice.

- **Slices** - are consectutive bits of an output port that are part (or all) of an input port. Examples using verilog syntax are Reg[7], Reg[3:2], etc. The notation Reg denotes all the bits of node Reg. If an input port is the concatenation of many slices, it must be connected to the output of a concat device. Each input port must be connected to a single node, which might be the output node of a concat gate.

- **Concats** - a concat gate is used to join one or most often multiple slices into a single node that will then be used to drive an input port of a component.


## Kahn's sorting algorithm

Every circuit will have its components sorted using Kahn's sorting algorithm before simulation

- **Drivers** - a component is not evaluated until all of its drivers have been evaluated. During the sorting, this is considered to be the case when its reference count is zero.

- **Reference Count** - before sorting is started, the reference counts of all components is determined. When a component input port is connected to either the parent's input, or to the output of a sync gate or Circuit, it's reference count is not increased. Only when it is connected to a node being driven by an async gate or Circuit, is its referenc count increased.

- **Zero Count** - any component with a reference count of zero can be evaluated. This is done using a first-in first out queue called evalQueue

- **Reference Count Decrement** - whenever a component having a reference count of zero is popped from evalQueue, all the sink components connected to the nodes of its output ports have their reference counts decremented. Any component reference popped from the evalQueue is pushed to the evalOrder Queue. If their reference count reaches zero, a reference to the component is pushed onto evalQueue.

- **Finish Checks** - after the algorithm terminates, the number of reference on the evalOrder queue must be equal to the original number reference counts. Also, the evalQueue must be empty.

