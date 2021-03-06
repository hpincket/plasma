%-----------------------------------------------------------------------%
% vim: ts=4 sw=4 et
%-----------------------------------------------------------------------%
:- module pz.pretty.
%
% PZ pretty printer
%
% Copyright (C) 2015-2018 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
%-----------------------------------------------------------------------%
:- interface.

:- import_module cord.
:- import_module string.

:- func pz_pretty(pz) = cord(string).

%-----------------------------------------------------------------------%
:- implementation.

:- import_module require.

:- import_module pretty_utils.
:- import_module q_name.
:- import_module util.

pz_pretty(PZ) = condense(StructsPretty) ++ nl ++ condense(DataPretty) ++ nl
        ++ condense(ProcsPretty) :-
    StructsPretty = from_list(map(struct_pretty, pz_get_structs(PZ))),
    DataPretty = from_list(map(data_pretty, pz_get_data_items(PZ))),
    ProcsPretty = from_list(map(proc_pretty(PZ), pz_get_procs(PZ))).

%-----------------------------------------------------------------------%

:- func struct_pretty(pair(pzs_id, pz_struct)) = cord(string).

struct_pretty(SID - pz_struct(Fields)) = String :-
    SIDNum = pzs_id_get_num(SID),

    String = from_list(["struct ", string(SIDNum), " = { "]) ++
        join(comma ++ spc, map(width_pretty, Fields)) ++ singleton(" }\n").

%-----------------------------------------------------------------------%

:- func data_pretty(pair(pzd_id, pz_data)) = cord(string).

data_pretty(DID - pz_data(Type, Values)) = String :-
    DIDNum = pzd_id_get_num(DID),
    DeclStr = format("data d%d = ", [i(DIDNum)]),

    TypeStr = data_type_pretty(Type),

    DataStr = singleton("{ ") ++ join(spc,
            map(data_value_pretty, Values)) ++
        singleton(" }"),

    String = singleton(DeclStr) ++ TypeStr ++ spc ++ DataStr ++ semicolon ++ nl.

:- func data_type_pretty(pz_data_type) = cord(string).

data_type_pretty(type_array(Width)) = cons("array(",
    snoc(width_pretty(Width), ")")).
data_type_pretty(type_struct(StructId)) = singleton(StructName) :-
    StructName = format("struct_%d", [i(pzs_id_get_num(StructId))]).

:- func data_value_pretty(pz_data_value) = cord(string).

data_value_pretty(pzv_num(Num)) =
    singleton(string(Num)).
data_value_pretty(Value) =
        singleton(format("%s%i", [s(Label), i(IdNum)])) :-
    ( Value = pzv_data(DID),
        Label = "d",
        IdNum = pzd_id_get_num(DID)
    ; Value = pzv_import(IID),
        Label = "i",
        IdNum = pzi_id_get_num(IID)
    ).

%-----------------------------------------------------------------------%

:- func proc_pretty(pz, pair(pzp_id, pz_proc)) = cord(string).

proc_pretty(PZ, PID - Proc) = String :-
    Name = format("%s_%d",
        [s(q_name_to_string(Proc ^ pzp_name)), i(pzp_id_get_num(PID))]),
    Inputs = Proc ^ pzp_signature ^ pzs_before,
    Outputs = Proc ^ pzp_signature ^ pzs_after,
    ParamsStr = join(spc, map(width_pretty, Inputs)) ++
        singleton(" - ") ++
        join(spc, map(width_pretty, Outputs)),

    DeclStr = singleton("proc ") ++ singleton(Name) ++ singleton(" (") ++
        ParamsStr ++ singleton(")"),

    MaybeBlocks = Proc ^ pzp_blocks,
    ( MaybeBlocks = yes(Blocks),
        ( Blocks = [],
            unexpected($file, $pred, "no blocks")
        ; Blocks = [Block],
            BlocksStr = pretty_block(PZ, Block)
        ; Blocks = [_, _ | _],
            map_foldl(pretty_block_with_name(PZ), Blocks, BlocksStr0, 0, _),
            BlocksStr = cord_list_to_cord(BlocksStr0)
        ),
        BodyStr = singleton(" {\n") ++ BlocksStr ++ singleton("}")
    ; MaybeBlocks = no,
        BodyStr = init
    ),

    String = DeclStr ++ BodyStr ++ semicolon ++ nl ++ nl.

:- pred pretty_block_with_name(pz::in, pz_block::in, cord(string)::out,
    int::in, int::out) is det.

pretty_block_with_name(PZ, pz_block(Instrs), String, !Num) :-
    String = indent(2) ++ singleton(format("block b%d {\n", [i(!.Num)])) ++
        pretty_instrs(PZ, 4, Instrs) ++
        indent(2) ++ singleton("}\n"),
    !:Num = !.Num + 1.

:- func pretty_block(pz, pz_block) = cord(string).

pretty_block(PZ, pz_block(Instrs)) = pretty_instrs(PZ, 2, Instrs).

:- func pretty_instrs(pz, int, list(pz_instr_obj)) = cord(string).

pretty_instrs(_, _, []) = init.
pretty_instrs(PZ, Indent, [Instr | Instrs]) =
    indent(Indent) ++ pretty_instr_obj(PZ, Instr) ++ nl ++
        pretty_instrs(PZ, Indent, Instrs).

:- func pretty_instr_obj(pz, pz_instr_obj) = cord(string).

pretty_instr_obj(PZ, pzio_instr(Instr)) = pretty_instr(PZ, Instr).
pretty_instr_obj(_, pzio_comment(Comment)) =
    singleton("// ") ++ singleton(Comment).

:- func pretty_instr(pz, pz_instr) = cord(string).

pretty_instr(PZ, Instr) = String :-
    ( Instr = pzi_load_immediate(Width, Value),
        (
            ( Value = immediate8(_)
            ; Value = immediate16(_)
            ; Value = immediate32(_)
            ; Value = immediate64(_, _)
            ),
            (
                ( Value = immediate8(Num)
                ; Value = immediate16(Num)
                ; Value = immediate32(Num)
                ),
                NumStr = singleton(string(Num))
            ; Value = immediate64(High, Low),
                NumStr = singleton(format("%d<<32+%d", [i(High),i(Low)]))
            ),
            String = NumStr ++ colon ++ width_pretty(Width)
        )
    ;
        ( Instr = pzi_ze(Width1, Width2),
            Name = "ze"
        ; Instr = pzi_se(Width1, Width2),
            Name = "se"
        ; Instr = pzi_trunc(Width1, Width2),
            Name = "trunc"
        ),
        String = singleton(Name) ++ colon ++
            width_pretty(Width1) ++ comma ++ width_pretty(Width2)
    ;
        ( Instr = pzi_add(Width),
            Name = "add"
        ; Instr = pzi_sub(Width),
            Name = "sub"
        ; Instr = pzi_mul(Width),
            Name = "mul"
        ; Instr = pzi_div(Width),
            Name = "div"
        ; Instr = pzi_mod(Width),
            Name = "mod"
        ; Instr = pzi_lshift(Width),
            Name = "lshift"
        ; Instr = pzi_rshift(Width),
            Name = "rshift"
        ; Instr = pzi_and(Width),
            Name = "and"
        ; Instr = pzi_or(Width),
            Name = "or"
        ; Instr = pzi_xor(Width),
            Name = "xor"
        ; Instr = pzi_lt_u(Width),
            Name = "lt_u"
        ; Instr = pzi_lt_s(Width),
            Name = "lt_s"
        ; Instr = pzi_gt_u(Width),
            Name = "gt_u"
        ; Instr = pzi_gt_s(Width),
            Name = "gt_s"
        ; Instr = pzi_eq(Width),
            Name = "eq"
        ; Instr = pzi_not(Width),
            Name = "not"
        ; Instr = pzi_cjmp(Dest, Width),
            Name = format("cjmp b%d", [i(Dest)])
        ),
        String = singleton(Name) ++ colon ++ width_pretty(Width)
    ;
        Instr = pzi_tcall(PID),
        String = singleton("tcall") ++ spc ++
            singleton(q_name_to_string(pz_lookup_proc(PZ, PID) ^ pzp_name))
    ; Instr = pzi_call(Callee),
        ( Callee = pzc_proc(PID),
            CalleeName = pz_lookup_proc(PZ, PID) ^ pzp_name
        ; Callee = pzc_import(IID),
            CalleeName = pz_lookup_import(PZ, IID)
        ),
        String = singleton("call") ++ spc ++
            singleton(q_name_to_string(CalleeName))
    ;
        ( Instr = pzi_drop,
            Name = "drop"
        ; Instr = pzi_call_ind,
            Name = "call_ind"
        ; Instr = pzi_jmp(Dest),
            Name = format("jmp %d", [i(Dest)])
        ; Instr = pzi_ret,
            Name = "ret"
        ; Instr = pzi_get_env,
            Name = "get_env"
        ),
        String = singleton(Name)
    ;
        ( Instr = pzi_roll(N),
            Name = "roll "
        ; Instr = pzi_pick(N),
            Name = "pick "
        ),
        String = singleton(Name) ++ singleton(string(N))
    ; Instr = pzi_alloc(Struct),
        String = singleton(format("alloc struct_%d",
            [i(pzs_id_get_num(Struct))]))
    ; Instr = pzi_make_closure(Proc),
        String = singleton(format("make_closure_%d",
            [i(pzp_id_get_num(Proc))]))
    ;
        ( Instr = pzi_load(Struct, Field, Width),
            Name = "load"
        ; Instr = pzi_store(Struct, Field, Width),
            Name = "store"
        ),
        String = singleton(Name) ++ colon ++ width_pretty(Width) ++ spc ++
            singleton(string(pzs_id_get_num(Struct))) ++ spc ++
            singleton(string(Field))
    ; Instr = pzi_load_named(ImportId, Width),
        String = singleton("load_named") ++ colon ++ width_pretty(Width) ++
            spc ++ singleton("import_") ++
            singleton(string(pzi_id_get_num(ImportId)))
    ).

:- func width_pretty(pz_width) = cord(string).

width_pretty(Width) = singleton(width_pretty_str(Width)).

:- func width_pretty_str(pz_width) = string.

width_pretty_str(pzw_8)    = "w8".
width_pretty_str(pzw_16)   = "w16".
width_pretty_str(pzw_32)   = "w32".
width_pretty_str(pzw_64)   = "w64".
% TODO: check that these match what the parser expects, standardize on some
% names for these throughout the system.
width_pretty_str(pzw_fast) = "w".
width_pretty_str(pzw_ptr)  = "ptr".

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
