%-----------------------------------------------------------------------%
% Utility code
% vim: ts=4 sw=4 et
%
% Copyright (C) 2015-2018 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
%-----------------------------------------------------------------------%
:- module util.

:- interface.

:- import_module bag.
:- import_module cord.
:- import_module io.
:- import_module list.
:- import_module maybe.
:- import_module set.
:- import_module string.

:- import_module context.

%-----------------------------------------------------------------------%

    % Print the error to stderror and set the exit code to 1.
    %
    % Does not terminate the program.
    %
:- pred exit_error(string::in, io::di, io::uo) is det.

    % maybe_default(_, yes(X)) = X.
    % maybe_default(D, no)     = D.
    %
    % TODO: This has been added to the Mercury standard library, but isn't
    % available in 14.01.1, which is the most recent Mercury that we
    % maintain compatibility with.
    %
:- func maybe_default(X, maybe(X)) = X.

    % one_item([X]) = X.
    %
:- func one_item(list(T)) = T.

:- func maybe_list(maybe(X)) = list(X).

:- func maybe_cord(maybe(X)) = cord(X).

    % set_map_foldl2(Pred, Set0, Set, !Acc1, !Acc2),
    %
:- pred set_map_foldl2(pred(X, Y, A, A, B, B),
    set(X), set(Y), A, A, B, B).
:- mode set_map_foldl2(pred(in, out, in, out, in, out) is det,
    in, out, in, out, in, out) is det.

:- pred map2_corresponding(pred(X, A, Y, B), list(X), list(A), list(Y),
    list(B)).
:- mode map2_corresponding(pred(in, out, in, out) is det, in, out, in, out)
    is det.

:- pred foldl4_corresponding(pred(X, Y, A, A, B, B, C, C, D, D),
    list(X), list(Y), A, A, B, B, C, C, D, D).
:- mode foldl4_corresponding(
    pred(in, in, in, out, in, out, in, out, in, out) is det,
    in, in, in, out, in, out, in, out, in, out) is det.


:- pred remove_first_match_map(pred(X, Y), Y, list(X), list(X)).
:- mode remove_first_match_map(pred(in, out) is semidet, out, in, out)
    is semidet.

%-----------------------------------------------------------------------%

:- func bag_list_to_bag(list(bag(T))) = bag(T).

%-----------------------------------------------------------------------%

    % This exception and its routines are temporary, they should be used for
    % code that finds a compilation error, but error handling is not
    % properly setup in that area of the compiler.  This helps by making
    % these errors a little more friendly, and by allowing us to search the
    % source code for these locations when we eventually add error handling.
    %
:- type compile_error_exception
    --->    compile_error_exception(string, string, maybe(context), string).

:- pred compile_error(string::in, string::in, string::in) is erroneous.

:- pred compile_error(string::in, string::in, context::in, string::in)
    is erroneous.

    % This is an alternative to the sorry/1 predicate in the Mercury
    % standard library.  This predicate uses a dedicated exception type and
    % is caught explicitly by plasmac's main/2 predicate.
    %
:- type unimplemented_exception
    --->    unimplemented_exception(string, string, string).

:- pred sorry(string::in, string::in, string::in) is erroneous.

:- func sorry(string, string, string) = T.
:- mode sorry(in, in, in) = (out) is erroneous.

    % Like sorry except that these exceptions are used for things we think
    % are unlikely.  Like trying to roll more than 256 items on the PZ
    % stack.  If they happen to real people then we'll try to address them
    % and can probably do something about them.
    %
:- type design_limitation_exception
    --->    design_limitation_exception(string, string, string).

:- pred limitation(string::in, string::in, string::in) is erroneous.

% TODO: add "unexpected" exception.

:- type tool
    --->    plasmac
    ;       pzasm.

:- type had_errors
    --->    had_errors
    ;       did_not_have_errors.

:- pred run_and_catch(pred(io, io), tool, had_errors, io, io).
:- mode run_and_catch(pred(di, uo) is det, in, out, di, uo) is cc_multi.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- implementation.

:- import_module exception.
:- import_module pair.
:- import_module require.

%-----------------------------------------------------------------------%

exit_error(ErrMsg, !IO) :-
    write_string(stderr_stream, ErrMsg ++ "\n", !IO),
    set_exit_status(1, !IO).

%-----------------------------------------------------------------------%

maybe_default(_, yes(X)) = X.
maybe_default(D, no) = D.

one_item(Xs) =
    ( if Xs = [X] then
        X
    else
        unexpected($file, $pred, "Expected a list with only one item")
    ).

%-----------------------------------------------------------------------%

maybe_list(yes(X)) = [X].
maybe_list(no) = [].

%-----------------------------------------------------------------------%

maybe_cord(yes(X)) = singleton(X).
maybe_cord(no) = init.

%-----------------------------------------------------------------------%

set_map_foldl2(Pred, Set0, Set, !Acc1, !Acc2) :-
    List0 = to_sorted_list(Set0),
    list.map_foldl2(Pred, List0, List, !Acc1, !Acc2),
    Set = set(List).

%-----------------------------------------------------------------------%

map2_corresponding(_, [],       [],       [],       []).
map2_corresponding(_, [],       _,        [_ | _],  _) :-
    unexpected($file, $pred, "Second list too long").
map2_corresponding(_, [_ | _],  _,        [],       _) :-
    unexpected($file, $pred, "First list too long").
map2_corresponding(P, [X | Xs], [A | As], [Y | Ys], [B | Bs]) :-
    P(X, A, Y, B),
    map2_corresponding(P, Xs, As, Ys, Bs).

foldl4_corresponding(_, [], [], !A, !B, !C, !D).
foldl4_corresponding(_, [_ | _], [], !A, !B, !C, !D) :-
    unexpected($file, $pred, "Input lists of different lengths").
foldl4_corresponding(_, [], [_ | _], !A, !B, !C, !D) :-
    unexpected($file, $pred, "Input lists of different lengths").
foldl4_corresponding(P, [X | Xs], [Y | Ys], !A, !B, !C, !D) :-
    P(X, Y, !A, !B, !C, !D),
    foldl4_corresponding(P, Xs, Ys, !A, !B, !C, !D).

%-----------------------------------------------------------------------%

remove_first_match_map(Pred, Y, [X | Xs], Ys) :-
    ( if Pred(X, YP) then
        Y = YP,
        Ys = Xs
    else
        remove_first_match_map(Pred, Y, Xs, Ys0),
        Ys = [X | Ys0]
    ).

%-----------------------------------------------------------------------%

bag_list_to_bag(LoB) =
    foldl(union, LoB, init).

%-----------------------------------------------------------------------%

compile_error(File, Pred, Message) :-
    throw(compile_error_exception(File, Pred, no, Message)).

compile_error(File, Pred, Context, Message) :-
    throw(compile_error_exception(File, Pred, yes(Context), Message)).

sorry(File, Pred, Message) :-
    throw(unimplemented_exception(File, Pred, Message)).
sorry(File, Pred, Message) = _ :-
    util.sorry(File, Pred, Message).

limitation(File, Pred, Message) :-
    throw(design_limitation_exception(File, Pred, Message)).

%-----------------------------------------------------------------------%

run_and_catch(Run, Tool, HadErrors, !IO) :-
    ( try [io(!IO)] (
        Run(!IO)
    ) then
        HadErrors = did_not_have_errors
    catch compile_error_exception(File, Pred, MbCtx, Msg) ->
        HadErrors = had_errors,
        Description =
"A compilation error occured and this error is not handled gracefully\n" ++
"by the " ++ tool_name(Tool) ++ ". Sorry.",
        ShortName = tool_short_name(Tool),
        ( MbCtx = yes(Ctx),
            print_exception(Description,
                ["Message"                  - Msg,
                 "Context"                  - context_string(Ctx),
                 (ShortName ++ " location") - Pred,
                 (ShortName ++ " file")     - File],
                !IO)
        ; MbCtx = no,
            print_exception(Description,
                ["Message"                  - Msg,
                 (ShortName ++ " location") - Pred,
                 (ShortName ++ " file")     - File],
                !IO)
        )
    catch unimplemented_exception(File, Pred, Feature) ->
        HadErrors = had_errors,
        print_exception(
"A feature required by your program is currently unimplemented,\n" ++
"however this is something we hope to implement in the future. Sorry\n",
            ["Feature"  - Feature,
             "Location" - Pred,
             "File"     - File],
            !IO)
    catch design_limitation_exception(File, Pred, Message) ->
        HadErrors = had_errors,
        print_exception(
"This program pushes Plasma beyond what it is designed to do. If this\n" ++
"happens on real programs (not a stress test) please contact us and\n" ++
"we'll do what we can to fix it.",
        ["Message"  - Message,
         "Location" - Pred,
         "File"     - File],
        !IO)
    catch software_error(Message) ->
        HadErrors = had_errors,
        print_exception(
"The " ++ tool_name(Tool) ++
    " has crashed due to a bug (an assertion failure or\n" ++
"unhandled state). Please make a bug report. Sorry.",
            ["Message" - Message], !IO)
    ).

:- pred print_exception(string::in, list(pair(string, string))::in,
    io::di, io::uo) is det.

print_exception(Message, Fields, !IO) :-
    write_string(stderr_stream, Message, !IO),
    io.nl(!IO),
    foldl(exit_exception_field, Fields, !IO).

:- pred exit_exception_field(pair(string, string)::in, io::di, io::uo)
    is det.

exit_exception_field(Name - Value, !IO) :-
    write_string(pad_right(Name ++ ": ", ' ', 20), !IO),
    write_string(Value, !IO),
    nl(!IO).

:- func tool_name(tool) = string.

tool_name(plasmac) = "Plasma compiler".
tool_name(pzasm) = "Plasma bytecode assembler".

:- func tool_short_name(tool) = string.

tool_short_name(T) = string(T).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
