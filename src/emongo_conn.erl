%% Copyright (c) 2009 Jacob Vorreuter <jacob.vorreuter@gmail.com>
%% 
%% Permission is hereby granted, free of charge, to any person
%% obtaining a copy of this software and associated documentation
%% files (the "Software"), to deal in the Software without
%% restriction, including without limitation the rights to use,
%% copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the
%% Software is furnished to do so, subject to the following
%% conditions:
%% 
%% The above copyright notice and this permission notice shall be
%% included in all copies or substantial portions of the Software.
%% 
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
%% EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
%% OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
%% NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
%% HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
%% WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
%% FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
%% OTHER DEALINGS IN THE SOFTWARE.
-module(emongo_conn).

-export([start_link/2, init/3, send/3, send_recv/3]).

-record(request, {req_id, requestor}).
-record(state, {socket, requests}).

-include("emongo.hrl").

start_link(Host, Port) ->
	proc_lib:start_link(?MODULE, init, [Host, Port, self()]).
	
init(Host, Port, Parent) ->
	Socket = open_socket(Host, Port),
	proc_lib:init_ack(Parent, self()),
	loop(#state{socket=Socket, requests=[]}).
	
send(Pid, ReqID, Packet) ->
	gen:call(Pid, '$emongo_conn_send', {ReqID, Packet}).
	
send_recv(Pid, ReqID, Packet) ->
	gen:call(Pid, '$emongo_conn_send_recv', {ReqID, Packet}).
	
loop(State) ->
	receive
		{'$emongo_conn_send', {From, Mref}, {_ReqID, Packet}} ->
			gen_tcp:send(State#state.socket, Packet),
			gen:reply({From, Mref}, ok),
			loop(State);
		{'$emongo_conn_send_recv', {From, Mref}, {ReqID, Packet}} -> 
			gen_tcp:send(State#state.socket, Packet),
			gen:reply({From, Mref}, ok),
			Request = #request{req_id=ReqID, requestor={From, Mref}},
			State1 = State#state{requests=[Request|State#state.requests]},
			loop(State1);
		{tcp, _Sock, Data} ->
			Resp = emongo_packet:decode_response(Data),
			ResponseTo = (Resp#response.header)#header.responseTo,
			case proplists:get_value(ResponseTo, State#state.requests) of
				undefined ->
					ok;
				Requestor ->
					gen:reply(Requestor, Resp)
			end,
			loop(State)
	end.
	
open_socket(Host, Port) ->
	case gen_tcp:connect(Host, Port, [binary, {active, true}]) of
		{ok, Sock} ->
			Sock;
		{error, Reason} ->
			exit({failed_to_open_socket, Reason})
	end.