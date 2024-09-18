%%%
%%% This module is adapted from Gary Rennie's Termite library. Thank you Gary!
%%% https://github.com/Gazler/termite
%%%
-module(prim_tty_shim).
-export([takeover_prim_tty/0, read/2, write/3]).
-export_type([state/0, read/0]).

-opaque state() :: term().

-type read() :: {data, binary()} | {signal, winch | cont}.

-spec takeover_prim_tty() -> {ok, state()}.
takeover_prim_tty() ->
    % Unregister the existing prim_tty process.
    erlang:unregister(user_drv_writer),
    erlang:unregister(user_drv_reader),
    % Have this process take over.
    % Silence the logger for this as the BEAM complains.
    #{level := LoggerLevel} = logger:get_primary_config(),
    logger:set_primary_config(level, emergency),
    PrimTtyState = prim_tty:init(#{}),
    erlang:spawn(fun() ->
        timer:sleep(100),
        logger:set_primary_config(level, LoggerLevel)
    end),
    {ok, PrimTtyState}.

-spec read(term(), non_neg_integer()) -> {ok, read()} | {error, nil}.
read(State, Timeout) ->
    Ref = get_reader_ref(State),
    receive
        {Ref, Message} -> {ok, Message}
    after
        Timeout -> {error, nil}
    end.

-spec write(state(), binary(), non_neg_integer()) -> {ok, nil} | {error, nil}.
write(State0, Data, Timeout) when is_binary(Data) ->
    % Why do we do this?
    State1 = set_xn(State0, false),
    {Output, State2} = prim_tty:handle_request(State1, {putc, Data}),
    Ref = get_writer_ref(State2),
    prim_tty:write(State2, Output, self()),
    receive
        {Ref, ok} -> {ok, nil}
    after
        Timeout -> {error, nil}
    end.

set_xn(State, Value) ->
    state = erlang:element(1, State),
    erlang:setelement(16, State, Value).

get_reader_ref(State) ->
    state = erlang:element(1, State),
    {_pid, Ref} = erlang:element(3, State),
    true = erlang:is_reference(Ref),
    Ref.

get_writer_ref(State) ->
    state = erlang:element(1, State),
    {_pid, Ref} = erlang:element(4, State),
    true = erlang:is_reference(Ref),
    Ref.
