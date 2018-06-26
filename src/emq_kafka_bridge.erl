%%--------------------------------------------------------------------
%% Copyright (c) 2015-2017 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emq_kafka_bridge).

-include_lib("emqttd/include/emqttd.hrl").

-include_lib("emqttd/include/emqttd_protocol.hrl").

-include_lib("emqttd/include/emqttd_internal.hrl").
-import(string,[concat/2]).
-import(lists,[nth/2]). 


-export([load/1, unload/0]).

%% Hooks functions

-export([on_client_connected/3, on_client_disconnected/3]).

-export([on_client_subscribe/4, on_client_unsubscribe/4]).

-export([on_session_created/3, on_session_subscribed/4, on_session_unsubscribed/4, on_session_terminated/4]).

-export([on_message_publish/2, on_message_delivered/4, on_message_acked/4]).

%% Called when the plugin application start
load(Env) ->
	ekaf_init([Env]),
    emqttd:hook('client.connected', fun ?MODULE:on_client_connected/3, [Env]),
    emqttd:hook('client.disconnected', fun ?MODULE:on_client_disconnected/3, [Env]),
    emqttd:hook('client.subscribe', fun ?MODULE:on_client_subscribe/4, [Env]),
    emqttd:hook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4, [Env]),
    emqttd:hook('session.created', fun ?MODULE:on_session_created/3, [Env]),
    emqttd:hook('session.subscribed', fun ?MODULE:on_session_subscribed/4, [Env]),
    emqttd:hook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4, [Env]),
    emqttd:hook('session.terminated', fun ?MODULE:on_session_terminated/4, [Env]),
    emqttd:hook('message.publish', fun ?MODULE:on_message_publish/2, [Env]),
    emqttd:hook('message.delivered', fun ?MODULE:on_message_delivered/4, [Env]),
    emqttd:hook('message.acked', fun ?MODULE:on_message_acked/4, [Env]).

on_client_connected(ConnAck, Client = #mqtt_client{client_id = ClientId}, _Env) ->
    % io:format("client ~s connected, connack: ~w~n", [ClientId, ConnAck]),
    ConnectionTs = emqttd_time:now_to_secs(),
    ConnectionType = <<"connected">>,
    Str0 = <<"{\"deviceId\":\"">>,
    Str1 = <<"\", \"type\":\"">>,
    Str2 = <<"\", \"ts\":\"">>,
    Str3 = <<"}">>,
    Str4 = <<Str0/binary, ClientId/binary, Str1/binary, ConnectionType/binary, Str2/binary, ConnectionTs/binary, Str3/binary>>,
    {ok, KafkaTopic} = application:get_env(emq_kafka_bridge, values),
    ProduceTopic = proplists:get_value(kafka_events_producer_topic, KafkaTopic),
    ekaf:produce_async(ProduceTopic, Str4),
    {ok, Client}.

on_client_disconnected(Reason, _Client = #mqtt_client{client_id = ClientId}, _Env) ->
    % io:format("client ~s disconnected, reason: ~w~n", [ClientId, Reason]),
    ConnectionTs = emqttd_time:now_to_secs(),
    ConnectionType = <<"disconnected">>,
    Str0 = <<"{\"deviceId\":\"">>,
    Str1 = <<"\", \"type\":\"">>,
    Str2 = <<"\", \"ts\":\"">>,
    Str3 = <<"}">>,
    Str4 = <<Str0/binary, ClientId/binary, Str1/binary, ConnectionType/binary, Str2/binary, ConnectionTs/binary, Str3/binary>>,
    {ok, KafkaTopic} = application:get_env(emq_kafka_bridge, values),
    ProduceTopic = proplists:get_value(kafka_events_producer_topic, KafkaTopic),
    ekaf:produce_async(ProduceTopic, Str4),
    ok.

on_client_subscribe(ClientId, Username, TopicTable, _Env) ->
    % io:format("client(~s/~s) will subscribe: ~p~n", [Username, ClientId, TopicTable]),
    {ok, TopicTable}.
    
on_client_unsubscribe(ClientId, Username, TopicTable, _Env) ->
    % io:format("client(~s/~s) unsubscribe ~p~n", [ClientId, Username, TopicTable]),
    {ok, TopicTable}.

on_session_created(ClientId, Username, _Env) ->
    io:format("session(~s/~s) created.", [ClientId, Username]),
    {ok, ClientId}.

on_session_subscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    % io:format("session(~s/~s) subscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    {ok, {Topic, Opts}}.

on_session_unsubscribed(ClientId, Username, {Topic, Opts}, _Env) ->
    % io:format("session(~s/~s) unsubscribed: ~p~n", [Username, ClientId, {Topic, Opts}]),
    ok.

on_session_terminated(ClientId, Username, Reason, _Env) ->
    % io:format("session(~s/~s) terminated: ~p.", [ClientId, Username, Reason])
    {ok, Reason}.

%% transform message and return
on_message_publish(Message = #mqtt_message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message}.

on_message_publish(Message = #mqtt_message{topic = Topic}, _Env) ->
    io:format("publish ~s~n", [emqttd_message:format(Message)]),
    Dup = Message#mqtt_message.dup,
    Retain = Message#mqtt_message.retain,
    Payload = Message#mqtt_message.payload,
    From = Message#mqtt_message.from,
    Qos = Message#mqtt_message.qos,
    PkgId = Message#mqtt_message.pktid,
    {ClientId} = From,
    Str0 = <<"{\"topic\":\"">>,
    Str1 = <<"\", \"deviceId\":\"">>,
    Str2 = <<"\", \"payload\":[">>,
    Str3 = <<"]}">>,
    Str4 = <<Str0/binary, Topic/binary, Str1/binary, ClientId/binary, Str2/binary, Payload/binary, Str3/binary>>,
	{ok, KafkaTopic} = application:get_env(emq_kafka_bridge, values),
    ProduceTopic = proplists:get_value(kafka_payload_producer_topic, KafkaTopic),
    ekaf:produce_async(ProduceTopic, Str4),	
    {ok, Message}.


on_message_delivered(ClientId, Username, Message, _Env) ->
    % io:format("delivered to client(~s/~s): ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    {ok, Message}.

on_message_acked(ClientId, Username, Message, _Env) ->
    % io:format("client(~s/~s) acked: ~s~n", [Username, ClientId, emqttd_message:format(Message)]),
    {ok, Message}.

ekaf_init(_Env) ->
    {ok, Values} = application:get_env(emq_kafka_bridge, values),
    BootstrapBroker = proplists:get_value(bootstrap_broker, Values),
    PartitionStrategy= proplists:get_value(partition_strategy, Values),
    application:set_env(ekaf, ekaf_partition_strategy, PartitionStrategy),
    application:set_env(ekaf, ekaf_bootstrap_broker, BootstrapBroker),
    {ok, _} = application:ensure_all_started(ekaf).
    % ,io:format("Initialized ekaf with ~p~n", [{"localhost", 9092}]).

%% Called when the plugin application stop
unload() ->
    emqttd:unhook('client.connected', fun ?MODULE:on_client_connected/3),
    emqttd:unhook('client.disconnected', fun ?MODULE:on_client_disconnected/3),
    emqttd:unhook('client.subscribe', fun ?MODULE:on_client_subscribe/4),
    emqttd:unhook('client.unsubscribe', fun ?MODULE:on_client_unsubscribe/4),
    emqttd:unhook('session.subscribed', fun ?MODULE:on_session_subscribed/4),
    emqttd:unhook('session.unsubscribed', fun ?MODULE:on_session_unsubscribed/4),
    emqttd:unhook('message.publish', fun ?MODULE:on_message_publish/2),
    emqttd:unhook('message.delivered', fun ?MODULE:on_message_delivered/4),
    emqttd:unhook('message.acked', fun ?MODULE:on_message_acked/4).
