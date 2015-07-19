%-----------------------------------------------------------------------%
% vim: ts=4 sw=4 et
%-----------------------------------------------------------------------%
:- module pzt_parse.
%
% Parse the PZ textual representation.
%
% Copyright (C) 2015 Paul Bone
% All rights reserved
%
%-----------------------------------------------------------------------%

:- interface.

%-----------------------------------------------------------------------%

:- import_module io.
:- import_module string.

:- import_module asm_ast.
:- import_module asm_error.
:- import_module result.

:- pred parse(string::in, result(asm, asm_error)::out, io::di, io::uo) is det.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module list.
:- import_module map.
:- import_module maybe.
:- import_module pair.

:- import_module context.
:- import_module lex.

%-----------------------------------------------------------------------%

parse(Filename, Result, !IO) :-
    io.open_input(Filename, OpenResult, !IO),
    ( OpenResult = ok(File),
        Lexer = lex.init(lexemes, lex.read_from_string),
        tokenize(File, Lexer, Filename, 1, [], TokensResult, !IO),
        io.close_input(File, !IO),
        ( TokensResult = ok(Tokens),
            parse_tokens(Tokens, Result)
        ; TokensResult = errors(Errors),
            Result = errors(Errors)
        )
    ; OpenResult = error(IOError),
        Error = error(context(Filename, 0), error,
            e_io_error(error_message(IOError))),
        Result = errors([Error])
    ).

%-----------------------------------------------------------------------%

    % tokenize(File, Lexer, Filename, Line, TokensAcc, Result, !LS, !IO)
    %
:- pred tokenize(text_input_stream::in, lexer(token_basic, string)::in,
    string::in, int::in,
    list(token)::in,
    result(list(token), asm_error)::out,
    io::di, io::uo) is det.

tokenize(File, Lexer, Filename, Line, RevTokens0, MaybeTokens, !IO) :-
    Context = context(Filename, Line),
    io.read_line_as_string(File, ReadResult, !IO),
    ( ReadResult = ok(String0),
        copy(String0 ++ "\n", String),
        LS0 = lex.start(Lexer, String),
        tokenize_line(Context, [], MaybeTokens0, LS0, LS),
        _ = lex.stop(LS),
        ( MaybeTokens0 = ok(NewTokens),
            RevTokens = NewTokens ++ RevTokens0,
            tokenize(File, Lexer, Filename, Line+1, RevTokens, MaybeTokens, !IO)
        ; MaybeTokens0 = errors(_),
            MaybeTokens = MaybeTokens0
        )
    ; ReadResult = eof,
        MaybeTokens = ok(reverse(RevTokens0))
    ; ReadResult = error(IOError),
        Error = error(Context, error, e_io_error(error_message(IOError))),
        MaybeTokens = errors([Error])
    ).

:- pred tokenize_line(context::in, list(token)::in,
    result(list(token), asm_error)::out,
    lexer_state(token_basic, string)::di,
    lexer_state(token_basic, string)::uo) is det.

tokenize_line(Context, RevTokens, MaybeTokens, !LS) :-
    lex.read(MaybeToken, !LS),
    ( MaybeToken = ok(Token),
        TAC = token(Token, Context),
        tokenize_line(Context, [TAC | RevTokens], MaybeTokens, !LS)
    ; MaybeToken = eof,
        MaybeTokens = ok(reverse(RevTokens))
    ; MaybeToken = error(Message, _Line),
        MaybeTokens = errors(
            [error(Context, error, e_tokeniser_error(Message))])
    ).

%-----------------------------------------------------------------------%

:- type token
    --->    token(
                tc_token        :: token_basic,
                tc_context      :: context
            ).

:- type token_basic
    --->    proc
    ;       open_curly
    ;       close_curly
    ;       open_paren
    ;       close_paren
    ;       dash
    ;       identifier(string)
    ;       string_constant(string)
    ;       comment
    ;       whitespace.

:- func lexemes = list(lexeme(token_basic)).

lexemes = [
        ("proc"             -> lex.return(proc)),
        ("{"                -> lex.return(open_curly)),
        ("}"                -> lex.return(close_curly)),
        ("("                -> lex.return(open_paren)),
        (")"                -> lex.return(close_paren)),
        ("-"                -> lex.return(dash)),
        (lex.identifier     -> (func(S) = identifier(S))),
        ('"' ++ (*(anybut("\""))) ++ '"'
                            -> (func(S) = string_constant(S))),
        ("//" ++ (*(anybut("\n")))
                            -> lex.return(comment)),
        (lex.whitespace     -> lex.return(whitespace))
    ].

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- pred parse_tokens(list(token)::in, result(asm, asm_error)::out)
    is det.

parse_tokens(Tokens, MaybePZT) :-
    parse_toplevel(Tokens, init, Entries, [], RevErrors),
    ( RevErrors = [],
        MaybePZT = ok(asm(Entries))
    ; RevErrors = [_ | _],
        MaybePZT = errors(reverse(RevErrors))
    ).

:- pred parse_toplevel(list(token)::in,
    asm_entries::in, asm_entries::out,
    errors(asm_error)::in, errors(asm_error)::out) is det.

parse_toplevel([], !Entries, !Errors).
parse_toplevel([token(Token, Context) | Tokens0], !Entries,
        !Errors) :-
    ( Token = proc ->
        parse_proc(Name, Proc, Tokens0, Tokens),
        Entry = asm_entry(Name, Context, Proc),
        ( add_entry(Name, Entry, !Entries) ->
            true
        ;
            add_error(Context, e_name_already_defined(Name),
                !Errors)
        )
    ;
        Tokens = Tokens0,
        add_error(Context, e_parse_error("Toplevel entry", string(Token)),
            !Errors)
    ),
    parse_toplevel(Tokens, !Entries, !Errors).

:- import_module require.

:- pred parse_proc(string::out, entry_type::out,
    list(token)::in, list(token)::out) is det.

parse_proc(_, _Proc, !Tokens) :-
    sorry($pred, "Unimplemented").

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%