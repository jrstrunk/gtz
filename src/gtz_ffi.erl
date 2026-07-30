%% Erlang target support for gtz, with no Elixir dependency.
-module(gtz_ffi).

-export([local_timezone/0, host_database/0]).

-define(DATABASE_KEY, {gtz_ffi, host_database}).

%% The TZif database to answer zone queries from, memoized in persistent_term.
%%
%% The operating system's own database is preferred, because it is the one the
%% rest of the machine agrees with and it is kept current by the system's
%% package manager. Parsing /usr/share/zoneinfo means reading several hundred
%% files, so it must not happen once per lookup, hence the memoization. If
%% there is no zoneinfo tree to read (a scratch container image, say), the
%% prebuilt database from the `zones` package is used instead, which is why
%% this lives here rather than in Gleam: `zones` is several megabytes and must
%% never be reachable from the JavaScript build.
%%
%% Returns the Gleam `Result(TzDatabase, Nil)`. Two processes racing here just
%% build the database twice and store the same thing, which is harmless.
host_database() ->
    case persistent_term:get(?DATABASE_KEY, undefined) of
        undefined ->
            Result =
                case tzif@database:load_from_os() of
                    {ok, Database} -> {ok, Database};
                    {error, _} -> {ok, zones:database()}
                end,
            persistent_term:put(?DATABASE_KEY, Result),
            Result;
        Result ->
            Result
    end.

%% Host time zone detection. Mirrors what the standard C library and most tz
%% libraries do, in order:
%%
%%   1. The TZ environment variable (a leading ":" is stripped, per POSIX).
%%      A path value is reduced to the part after "zoneinfo/".
%%   2. The symlink target of /etc/localtime, which is how most Linux distros
%%      and macOS record the zone (macOS points into /var/db/timezone).
%%   3. The contents of /etc/timezone (Debian/Ubuntu) or
%%      /etc/sysconfig/clock (older RHEL/SUSE).
%%   4. "UTC" as a last resort.
%%
%% Only IANA-style names are accepted; POSIX TZ strings such as "EST5EDT,M3.2.0"
%% are not zone names and are skipped so a later source can answer.

local_timezone() ->
    first_ok([fun from_env/0, fun from_localtime_link/0, fun from_config_files/0], <<"UTC">>).

first_ok([], Default) ->
    Default;
first_ok([F | Rest], Default) ->
    case F() of
        {ok, Name} -> Name;
        error -> first_ok(Rest, Default)
    end.

from_env() ->
    case os:getenv("TZ") of
        false ->
            error;
        Value ->
            % POSIX allows a leading ":" to force the "implementation defined"
            % (i.e. file based) interpretation of the value.
            zone_name(string:trim(string:trim(Value, leading, ":")))
    end.

from_localtime_link() ->
    case file:read_link_all("/etc/localtime") of
        {ok, Target} -> zone_name(Target);
        {error, _} -> error
    end.

from_config_files() ->
    first_of([
        fun() -> read_zone_file("/etc/timezone") end,
        fun() -> read_clock_file("/etc/sysconfig/clock") end
    ]).

first_of([]) ->
    error;
first_of([F | Rest]) ->
    case F() of
        {ok, Name} -> {ok, Name};
        error -> first_of(Rest)
    end.

read_zone_file(Path) ->
    case file:read_file(Path) of
        {ok, Contents} -> zone_name(string:trim(Contents));
        {error, _} -> error
    end.

%% /etc/sysconfig/clock holds shell style assignments, one of which is
%% ZONE="Area/City".
read_clock_file(Path) ->
    case file:read_file(Path) of
        {error, _} ->
            error;
        {ok, Contents} ->
            Lines = string:split(Contents, "\n", all),
            case [L || L <- Lines, string:prefix(string:trim(L), "ZONE=") =/= nomatch] of
                [Line | _] ->
                    Value = string:prefix(string:trim(Line), "ZONE="),
                    zone_name(string:trim(string:trim(Value), both, "\"'"));
                [] ->
                    error
            end
    end.

%% Reduces a raw value to an IANA zone name, or `error` if it is not one.
zone_name(Value) ->
    Binary = unicode:characters_to_binary(Value),
    case Binary of
        <<>> ->
            error;
        _ ->
            % A path such as "/usr/share/zoneinfo/America/New_York" or the
            % relative "../usr/share/zoneinfo/America/New_York" keeps only the
            % part below the database root.
            Name =
                case string:split(Binary, <<"zoneinfo/">>, trailing) of
                    [_, Rest] -> Rest;
                    [Whole] -> Whole
                end,
            case is_zone_name(Name) of
                true -> {ok, Name};
                false -> error
            end
    end.

%% Zone names are relative paths of alphanumeric components, and may contain
%% "+", "-", "_" and ".". This rejects POSIX TZ strings (which contain digits
%% right after letters and often ",") and anything path-traversing.
is_zone_name(<<>>) ->
    false;
is_zone_name(Name) ->
    case binary:match(Name, [<<"..">>, <<",">>]) of
        nomatch ->
            binary:first(Name) =/= $/ andalso
                lists:all(fun is_zone_char/1, binary_to_list(Name)) andalso
                not is_posix_tz(Name);
        _ ->
            false
    end.

is_zone_char(C) ->
    (C >= $a andalso C =< $z) orelse
        (C >= $A andalso C =< $Z) orelse
        (C >= $0 andalso C =< $9) orelse
        lists:member(C, "/+-_.").

%% A POSIX TZ string like "EST5EDT" or "GMT0BST" has an offset digit that is
%% not preceded by "/" or one of the digits of a numbered zone such as
%% "Etc/GMT+5". Names containing no "/" but containing a digit are treated as
%% POSIX strings.
is_posix_tz(Name) ->
    binary:match(Name, <<"/">>) =:= nomatch andalso
        lists:any(fun(C) -> C >= $0 andalso C =< $9 end, binary_to_list(Name)).
