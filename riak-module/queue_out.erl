-module('queue_out').
-include_lib("amqp_client/include/amqp_client.hrl").
-export([queue_out/1]).

-define(AMQP_HOST, "127.0.0.1").
-define(AMQP_PORT, 5672).
-define(AMQP_USERNAME, "guest").
-define(AMQP_PASSWORD, "guest").
-define(AMQP_VHOST, "/").
-define(AMQP_EXCHANGE, "").
-define(AMQP_ROUTING_KEY, "Atlas").

-define(DEFAULT_CONTENT_TYPE, "application/octet-stream").

-define(HEADER_BUCKET, "X-Bucket").
-define(HEADER_KEY, "X-Key").
-define(HEADER_DELETED, "X-Deleted").

queue_out(RObj) ->

    % CHANNEL
    {ok, Channel} = pg2_channel(#amqp_params_network{
        host = ?AMQP_HOST,
        port = ?AMQP_PORT,
        username = list_to_binary(?AMQP_USERNAME),
        password = list_to_binary(?AMQP_PASSWORD),
        virtual_host = list_to_binary(?AMQP_VHOST)
    }),

    % PUBLISH
    Publish = #'basic.publish'{
        exchange = list_to_binary(?AMQP_EXCHANGE),
        routing_key = list_to_binary(?AMQP_ROUTING_KEY)
    },

    % PROPS
    Metadata = riak_object:get_metadata(RObj),
    ContentType = list_to_binary(case dict:find(<<"content-type">>, Metadata) of
        {ok, V} -> V;
        _ -> ?DEFAULT_CONTENT_TYPE
    end),
    Deleted = case dict:find(<<"X-Riak-Deleted">>, Metadata) of
        {ok, "true"} -> "true";
        _ -> "false"
    end,
    Headers = [
        {?HEADER_BUCKET, binary, riak_object:bucket(RObj)},
        {?HEADER_KEY, binary, riak_object:key(RObj)},
        {?HEADER_DELETED, binary, Deleted}
    ],
    Props = #'P_basic'{
        content_type = ContentType,
        headers = Headers
    },

    % BODY
    Body = riak_object:get_value(RObj),

    % MESSAGE
    Msg = #amqp_msg{
        props = Props,
        payload = Body
    },

    % SEND
    amqp_channel:cast(Channel, Publish, Msg).

pg2_channel(AmqpParams) ->
    case pg2:get_closest_pid(AmqpParams) of
        {error, {no_such_group, _}} -> pg2:create(AmqpParams), pg2_channel(AmqpParams);
        {error, {no_process, _}} -> {ok, Channel} = amqp_channel(AmqpParams), pg2:join(AmqpParams, Channel), {ok, Channel};
        Channel -> {ok, Channel}
    end.

amqp_channel(AmqpParams) ->
    case amqp_connection:start(AmqpParams) of
        {ok, Client} -> amqp_connection:open_channel(Client);
        {error, Reason} -> {error, Reason}
    end.
