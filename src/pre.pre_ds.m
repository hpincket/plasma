%-----------------------------------------------------------------------%
% Plasma pre-core representation
% vim: ts=4 sw=4 et
%
% Copyright (C) 2016-2017 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
% This module represents the pre-core representation.
%
%-----------------------------------------------------------------------%
:- module pre.pre_ds.
%-----------------------------------------------------------------------%

:- interface.

:- import_module list.
:- import_module map.
:- import_module set.

:- import_module common_types.
:- import_module varmap.

%-----------------------------------------------------------------------%

:- type pre_procedure
    --->    pre_procedure(
                p_func_id       :: func_id,
                p_varmap        :: varmap,
                p_param_vars    :: list(var_or_wildcard(var)),
                p_arity         :: arity,
                p_body          :: pre_statements,
                p_context       :: context
            ).

%-----------------------------------------------------------------------%

:- type pre_statements == list(pre_statement).

:- type pre_statement
    --->    pre_statement(
                s_type      :: pre_stmt_type,
                s_info      :: pre_stmt_info
            ).

:- type pre_stmt_type
    --->    s_call(pre_call)
    ;       s_assign(list(var_or_wildcard(var)), pre_expr)
    ;       s_return(list(var))
    ;       s_match(var, list(pre_case)).

:- type pre_stmt_info
    --->    stmt_info(
                si_context      :: context,

                    % Use vars the set of variables whose values are needed
                    % by this computation.  They appear on the LHS of
                    % assignments or anywhere within other statement types.
                si_use_vars     :: set(var),

                    % Def vars is the set of variables that are computed by
                    % this computation.  They appear on the RHS of
                    % assignments.  They may intersect with use vars, for
                    % example if this is a compound statement containing an
                    % assignment of a variable followed by the use of the
                    % same variable.
                si_def_vars     :: set(var),

                    % Non locals is the set of variables appearing in either
                    % use vars or def vars that also appear in the set of
                    % use vars or def vars of some other statement.
                si_non_locals   :: set(var),

                    % Whether the end of this statment is reachable.
                si_reachable    :: stmt_reachable
            ).

:- type stmt_reachable
    --->    stmt_always_fallsthrough
            % NOTE: All visible cases are covered, uncovered cases cannot be
            % detected until after typechecking.
    ;       stmt_always_returns
    ;       stmt_may_return.

:- type pre_call
    % XXX: Maybe use only variables as call arguments?
    --->    pre_call(func_id, list(pre_expr), with_bang)
    ;       pre_ho_call(pre_expr, list(pre_expr), with_bang).

:- type with_bang
    --->    with_bang
    ;       without_bang.

:- type pre_case
    --->    pre_case(pre_pattern, pre_statements).

:- type pre_pattern
    --->    p_number(int)
    ;       p_var(var)
    ;       p_constr(ctor_id, list(pre_pattern))
    ;       p_wildcard.

:- type pre_expr
    --->    e_call(pre_call)
    ;       e_var(var)
    ;       e_construction(
                ctor_id,
                list(pre_expr)
            )
    ;       e_constant(const_type).

%-----------------------------------------------------------------------%

:- func stmt_all_vars(pre_statement) = set(var).

:- func pattern_all_vars(pre_pattern) = set(var).

:- pred stmt_rename(set(var)::in, pre_statement::in, pre_statement::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

:- pred pat_rename(set(var)::in, pre_pattern::in, pre_pattern::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- implementation.

:- import_module util.

%-----------------------------------------------------------------------%

stmt_all_vars(pre_statement(Type, _)) = Vars :-
    ( Type = s_call(Call),
        Vars = call_all_vars(Call)
    ; Type = s_assign(LVarsOrWildcards, Expr),
        filter_map(vow_is_var, LVarsOrWildcards, LVars),
        Vars = set(LVars) `union` expr_all_vars(Expr)
    ; Type = s_return(RVars),
        Vars = set(RVars)
    ; Type = s_match(Var, Cases),
        Vars = make_singleton_set(Var) `union`
            union_list(map(case_all_vars, Cases))
    ).

:- func case_all_vars(pre_case) = set(var).

case_all_vars(pre_case(Pat, Stmts)) = pattern_all_vars(Pat) `union`
    union_list(map(stmt_all_vars, Stmts)).

pattern_all_vars(p_number(_)) = set.init.
pattern_all_vars(p_var(Var)) = make_singleton_set(Var).
pattern_all_vars(p_wildcard) = set.init.
pattern_all_vars(p_constr(_, Args)) =
    union_list(map(pattern_all_vars, Args)).

:- func expr_all_vars(pre_expr) = set(var).

expr_all_vars(e_call(Call)) = call_all_vars(Call).
expr_all_vars(e_var(Var)) = make_singleton_set(Var).
expr_all_vars(e_construction(_, Args)) = union_list(map(expr_all_vars, Args)).
expr_all_vars(e_constant(_)) = set.init.

:- func call_all_vars(pre_call) = set(var).

call_all_vars(pre_call(_, Exprs, _)) =
    union_list(map(expr_all_vars, Exprs)).
call_all_vars(pre_ho_call(CalleeExpr, ArgsExprs, _)) =
    union_list(map(expr_all_vars, ArgsExprs)) `union` expr_all_vars(CalleeExpr).

%-----------------------------------------------------------------------%

stmt_rename(Vars, pre_statement(Type0, Info0), pre_statement(Type, Info),
        !Renaming, !Varmap) :-
    ( Type0 = s_call(Call0),
        call_rename(Vars, Call0, Call, !Renaming, !Varmap),
        Type = s_call(Call)
    ; Type0 = s_assign(LVars0, Expr0),
        map_foldl2(var_or_wild_rename(Vars), LVars0, LVars, !Renaming, !Varmap),
        expr_rename(Vars, Expr0, Expr, !Renaming, !Varmap),
        Type = s_assign(LVars, Expr)
    ; Type0 = s_return(RVars0),
        map_foldl2(var_rename(Vars), RVars0, RVars, !Renaming, !Varmap),
        Type = s_return(RVars)
    ; Type0 = s_match(Var0, Cases0),
        var_rename(Vars, Var0, Var, !Renaming, !Varmap),
        map_foldl2(case_rename(Vars), Cases0, Cases, !Renaming, !Varmap),
        Type = s_match(Var, Cases)
    ),

    Info0 = stmt_info(Context, UseVars0, DefVars0, NonLocals0, StmtReturns),
    set_map_foldl2(var_rename(Vars), UseVars0, UseVars, !Renaming, !Varmap),
    set_map_foldl2(var_rename(Vars), DefVars0, DefVars, !Renaming, !Varmap),
    set_map_foldl2(var_rename(Vars), NonLocals0, NonLocals, !Renaming, !Varmap),
    Info = stmt_info(Context, UseVars, DefVars, NonLocals, StmtReturns).

:- pred case_rename(set(var)::in, pre_case::in, pre_case::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

case_rename(Vars, pre_case(Pat0, Stmts0), pre_case(Pat, Stmts),
        !Renaming, !Varmap) :-
    pat_rename(Vars, Pat0, Pat, !Renaming, !Varmap),
    map_foldl2(stmt_rename(Vars), Stmts0, Stmts, !Renaming, !Varmap).

pat_rename(_, p_number(N), p_number(N), !Renaming, !Varmap).
pat_rename(Vars, p_var(Var0), p_var(Var), !Renaming, !Varmap) :-
    var_rename(Vars, Var0, Var, !Renaming, !Varmap).
pat_rename(_, p_wildcard, p_wildcard, !Renaming, !Varmap).
pat_rename(Vars, p_constr(C, Args0), p_constr(C, Args), !Renaming, !Varmap) :-
    map_foldl2(pat_rename(Vars), Args0, Args, !Renaming, !Varmap).

:- pred expr_rename(set(var)::in, pre_expr::in, pre_expr::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

expr_rename(Vars, e_call(Call0), e_call(Call), !Renaming, !Varmap) :-
    call_rename(Vars, Call0, Call, !Renaming, !Varmap).
expr_rename(Vars, e_var(Var0), e_var(Var), !Renaming, !Varmap) :-
    var_rename(Vars, Var0, Var, !Renaming, !Varmap).
expr_rename(Vars, e_construction(C, Args0), e_construction(C, Args),
        !Renaming, !Varmap) :-
    map_foldl2(expr_rename(Vars), Args0, Args, !Renaming, !Varmap).
expr_rename(_, e_constant(C), e_constant(C), !Renaming, !Varmap).

:- pred call_rename(set(var)::in, pre_call::in, pre_call::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

call_rename(Vars, pre_call(Func, Exprs0, Bang), pre_call(Func, Exprs, Bang),
        !Renaming, !Varmap) :-
    map_foldl2(expr_rename(Vars), Exprs0, Exprs, !Renaming, !Varmap).
call_rename(Vars, pre_ho_call(CalleeExpr0, ArgExprs0, Bang),
        pre_ho_call(CalleeExpr, ArgExprs, Bang), !Renaming, !Varmap) :-
    expr_rename(Vars, CalleeExpr0, CalleeExpr, !Renaming, !Varmap),
    map_foldl2(expr_rename(Vars), ArgExprs0, ArgExprs, !Renaming, !Varmap).

:- pred var_or_wild_rename(set(var)::in,
    var_or_wildcard(var)::in, var_or_wildcard(var)::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

var_or_wild_rename(Vars, var(Var0), var(Var), !Renaming, !Varmap) :-
    var_rename(Vars, Var0, Var, !Renaming, !Varmap).
var_or_wild_rename(_, wildcard, wildcard, !Renaming, !Varmap).

:- pred var_rename(set(var)::in, var::in, var::out,
    map(var, var)::in, map(var, var)::out, varmap::in, varmap::out) is det.

var_rename(Vars, Var0, Var, !Renaming, !Varmap) :-
    ( if member(Var0, Vars) then
        ( if search(!.Renaming, Var0, VarPrime) then
            Var = VarPrime
        else
            % XXX: Create a variable with the same name.
            add_anon_var(Var, !Varmap),
            det_insert(Var0, Var, !Renaming)
        )
    else
        Var = Var0
    ).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
