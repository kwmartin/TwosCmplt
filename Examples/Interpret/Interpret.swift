import Foundation
import SharedTypes
import TwosCmplt
import Yams

// MARK: - Value & Label

// Stack helpers
func pop(_ ctx: inout Context) -> Value {
    guard let v = ctx.stack.popLast() else {
        fatalError("Stack underflow")
    }
    return v
}

func popInt(_ ctx: inout Context) -> Int {
    switch pop(&ctx) {
    case .int(let i): return i
    default: fatalError("Expected Int on stack")
    }
}

func popBool(_ ctx: inout Context) -> Bool {
    switch pop(&ctx) {
    case .bool(let b): return b
    default: fatalError("Expected Bool on stack")
    }
}

func popReal(_ ctx: inout Context) -> Double {
    switch pop(&ctx) {
    case .real(let r): return r
    default: fatalError("Expected Real on stack")
    }
}

var exps: [Exp] = [
    Exp(kind: "int", value: .int(16)),
    Exp(kind: "UMinus:", value: nil),      // operator
    Exp(kind: "int",  value: .int(42)),
    Exp(kind: "BMinus:", value: nil),       // operator
    Exp(kind: "ULessEq:", value: nil),    // operator
]

var Clk = Nod(TwoCmplt(0))
var A = Nod(TwoCmplt(42, nbits: 8))
var B = Nod(TwoCmplt(26, nbits: 8))
var C = Nod(TwoCmplt(0, nbits: 8))

var nodeLU: [String: Int] = [
    "Clk": 0,
    "A": 1,
    "B": 2,
    "C": 3
    ]

var nods: [Nod] = [Clk, A, B, C]

func execute(_ ctx: inout Context) {
    guard let code = ctx.block?.code else {
        fatalError("execute called with no compiled block in Context")
        // or: return, if you prefer a silent no‑op
    }

    var ip = 0

    while ip < code.count {
        switch code[ip] {

        case .nop:
            ip += 1

        case .label:
            // Labels are markers only
            ip += 1

        case .pushInt(let value):
            ctx.stack.append(.int(value))
            ip += 1

        case .pushBool(let value):
            ctx.stack.append(.bool(value))
            ip += 1

        case .loadVar(let name):
            let v = ctx.vars[name] ?? .int(0)
            ctx.stack.append(v)
            ip += 1

        case .greaterThanZero:
            let x = popInt(&ctx)
            ctx.stack.append(.bool(x > 0))
            ip += 1

        case .printString(let s):
            print(s)
            ip += 1

        case .jump(let label):
            ip = ctx.address(for: label)
            // continue (do not ip += 1)

        case .jumpIfFalse(let label):
            let cond = popBool(&ctx)
            if !cond {
                ip = ctx.address(for: label)
            } else {
                ip += 1
            }
        }
    }
}

// MARK: - Example program: nested if-then-else

/*
 High-level pseudo:

 if (a > 0) {
     if (b > 0) {
         print("both positive")
     } else {
         print("a positive, b not")
     }
 } else {
     print("a not positive")
 }
*/

let L_afterOuterIf   = Label(name: "after_outer_if")
let L_outerThen      = Label(name: "outer_then")
let L_outerElse      = Label(name: "outer_else")

let L_afterInnerIf   = Label(name: "after_inner_if")
let L_innerThen      = Label(name: "inner_then")
let L_innerElse      = Label(name: "inner_else")

// Pre/cond/body/post flattened into one code array for demo
let code: [Stmt] = [
    // --- Outer if cond: (a > 0) ---
    .loadVar("a"),               // push a
    .greaterThanZero,            // a > 0 -> Bool
    .jumpIfFalse(L_outerElse),   // if !(a > 0) goto outer_else

    // --- Outer then-branch ---
    .label(L_outerThen),

    // Inner if cond: (b > 0)
    .loadVar("b"),               // push b
    .greaterThanZero,            // b > 0 -> Bool
    .jumpIfFalse(L_innerElse),   // if !(b > 0) goto inner_else

    // Inner then:
    .label(L_innerThen),
    .printString("both positive"),
    .jump(L_afterInnerIf),

    // Inner else:
    .label(L_innerElse),
    .printString("a positive, b not"),
    .jump(L_afterInnerIf),

    // After inner if:
    .label(L_afterInnerIf),
    .jump(L_afterOuterIf),

    // --- Outer else-branch ---
    .label(L_outerElse),
    .printString("a not positive"),
    .jump(L_afterOuterIf),

    // --- After outer if ---
    .label(L_afterOuterIf),
    .nop
]

let config = try! ldYamlConfig()
let cirfl = config.directories.circLib + "DG_DR_3X1.yml"

guard let yamlString = try? getCircYmlStr(named: "DG_DR_3X1")
else { fatalError("Failed to read yamlString") }

guard var circDef: CircDef = try? YAMLDecoder().decode(CircDef.self, from: yamlString)
else { fatalError("Failed to load circDef") }

let behavAST = circDef.buildBehavAST()

// Compile: build label table
let compiled = CompiledBlock(code: code, labelToIP: buildLabelTable(for: code))

// Set up initial context with variable values
var ctx = Context( circDef: circDef,
                   block: compiled,
                   stack: [],
                   vars: ["a": .int(1), "b": .int(-1)])

var args: [Value] = []

let final = expEval(exps, args: args)
print("final: \(final)")
// Run
execute(&ctx)
