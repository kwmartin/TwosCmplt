type: subcirc
module: DG_DR_3X1
params:
-   type: Int
    name: delay
    value: 5
io_ports:
-   name: D
-   name: R
-   name: CLK
-   name: QP
-   name: VDD
-   name: VSS
decls:
-   -   type: Input
        name: D
        signed: 'False'
        width:
        - 0
        - 0
        length: []
    -   type: Input
        name: R
        signed: 'False'
        width:
        - 0
        - 0
        length: []
    -   type: Input
        name: CLK
        signed: 'False'
        width:
        - 0
        - 0
        length: []
-   -   type: Output
        name: QP
        signed: 'False'
        width:
        - 0
        - 0
        length: []
-   -   type: Input
        name: VDD
        signed: 'False'
        width:
        - 0
        - 0
        length: []
    -   type: Input
        name: VSS
        signed: 'False'
        width:
        - 0
        - 0
        length: []
-   -   type: Reg
        name: STATE
        signed: 'False'
        width:
        - 0
        - 0
        length: []
behav_blcks:
-   type: specify
    variant: full
    delay_expr:
    -   type: delay
        value: 31.5
    src_sgnls:
    - ident
    - CLK
    edge: negedge
    dst_sgnls:
    -   type: ident
        name: QP
    -   type: ident
        name: D
    -   - pthspc
        - pluscolon
-   type: specify
    variant: full
    delay_expr:
    -   type: delay
        value: 31.5
    src_sgnls:
    - ident
    - R
    edge: posedge
    dst_sgnls:
    - ident
    - QP
-   type: initial
    execs:
        type: block
        execs:
        -   type: blcksb_st
            lvalue:
                type: ident
                name: STATE
            rvalue:
                type: int
                value: 0
-   type: always
    onlyif:
    - negedge
    -   type: ident
        name: CLK
    - posedge
    -   type: ident
        name: R
    execs:
        type: block
        execs:
        -   type: ifst
            cond:
                type: cmpexpr
                oper: 'LessThan:'
                args:
                -   type: syscall
                    name: time
                    value: null
                -   type: float
                    value: 100.0
            iftrue:
                type: block
                execs:
                -   type: noblcksb_st
                    lvalue:
                        type: ident
                        name: STATE
                    rvalue:
                        type: int
                        value: 0
                -   type: ifst
                    cond:
                        type: cmpexpr
                        oper: 'Eql:'
                        args:
                        -   type: ident
                            name: R
                    iftrue:
                        type: block
                        execs:
                        -   type: noblcksb_st
                            lvalue:
                                type: ident
                                name: STATE
                            rvalue:
                                type: int
                                value: 0
                    ifelse:
                        type: block
                        execs:
                        -   type: noblcksb_st
                            lvalue:
                                type: ident
                                name: STATE
                            rvalue:
                                type: ident
                                name: D
-   type: assign
    lvalue:
        type: ident
        name: QP
    rvalue:
        type: ident
        name: STATE
    delay: 0
