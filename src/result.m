%-----------------------------------------------------------------------%
% Utility code
% vim: ts=4 sw=4 et
%
% Copyright (C) 2015 Paul Bone
% Distributed under the terms of the GPLv2 see ../LICENSE.tools
%
%-----------------------------------------------------------------------%
:- module result.

:- interface.

:- import_module io.
:- import_module cord.
:- import_module list.

:- import_module context.

%-----------------------------------------------------------------------%

:- type result(T, E)
    --->    ok(T)
    ;       errors(cord(error(E))).

:- type result_partial(T, E)
    --->    ok(T, cord(error(E)))
    ;       errors(cord(error(E))).

:- type errors(E) == cord(error(E)).

:- type error(E)
    --->    error(
                e_context       :: context,
                e_error         :: E
            ).

%-----------------------------------------------------------------------%

:- typeclass error(E) where [
        func to_string(E) = string,
        func error_or_warning(E) = error_or_warning
    ].

:- type error_or_warning
    --->    error
    ;       warning.

%-----------------------------------------------------------------------%

:- pred add_error(context::in, E::in, errors(E)::in, errors(E)::out)
    is det.

    % add_errors(NewErrors, !Errors)
    %
    % Add NewErrors to !Errors.
    %
:- pred add_errors(errors(E)::in, errors(E)::in, errors(E)::out) is det.

%-----------------------------------------------------------------------%

:- func return_error(context, E) = result(T, E).

%-----------------------------------------------------------------------%

:- pred report_errors(cord(error(E))::in, io::di, io::uo) is det
    <= error(E).

%-----------------------------------------------------------------------%

:- pred result_list_to_result(list(result(T, E))::in,
    result(list(T), E)::out) is det.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- implementation.

:- import_module list.
:- import_module string.

%-----------------------------------------------------------------------%

add_error(Context, ErrorType, !Errors) :-
    Error = error(Context, ErrorType),
    !:Errors = snoc(!.Errors, Error).

%-----------------------------------------------------------------------%

add_errors(NewErrors, !Errors) :-
    !:Errors = !.Errors ++ NewErrors.

%-----------------------------------------------------------------------%

return_error(Context, Error) =
    errors(singleton(error(Context, Error))).

%-----------------------------------------------------------------------%

report_errors(Errors, !IO) :-
    ErrorStrings = map(error_to_string, Errors),
    write_string(join_list("\n", list(ErrorStrings)), !IO),
    nl(!IO),
    set_exit_status(1, !IO).

:- func error_to_string(error(E)) = string <= error(E).

error_to_string(error(Context, Error)) = String :-
    Context = context(Filename, Line),
    ErrorStr = to_string(Error),
    format("%s:%d: %s", [s(Filename), i(Line), s(ErrorStr)],
        String).

%-----------------------------------------------------------------------%

result_list_to_result(Results, Result) :-
    list.foldl(build_result, Results, ok([]), Result0),
    ( Result0 = ok(RevList),
        Result = ok(reverse(RevList))
    ; Result0 = errors(_),
        Result = Result0
    ).

:- pred build_result(result(T, E)::in,
    result(list(T), E)::in, result(list(T), E)::out) is det.

build_result(ok(X), ok(Xs), ok([X | Xs])).
build_result(ok(_), R@errors(_), R).
build_result(errors(E), ok(_), errors(E)).
build_result(errors(E), errors(Es0), errors(Es)) :-
    add_errors(E, Es0, Es).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
