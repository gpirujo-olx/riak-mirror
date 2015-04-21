# riak-mirror

This is a couple of software pieces to mirror Riak's contents in S3.
The input side is an Erlang routine to be used at Riak's `postcommit` hook that takes the object just written and copies it to the queue.
The output side is a Node script that listens to the queue and creates, updates or deletes the object in S3.

# Input side: Riak module

## Install required libraries

You will need the [Rabbit Erlang Client](http://www.rabbitmq.com/erlang-client.html).
Download the `amqp_client` and `rabbit_common` packages.
You don't need the source.
If the latest version doesn't work, go back and download the one that matches the version of RabbitMQ you are using.

Uncompress the packages somewhere.
Add each package's `beams` directory to the `add_paths` key in Riak's `advanced.config` file.
You should find it (or create it) in the same directory where `riak.conf` is.
Here is an example `advanced.config` file.
```
[
    {riak_kv, [{add_paths, [
        "/Users/guillermo/erlang/beams/amqp_client/ebin/",
        "/Users/guillermo/erlang/beams/rabbit_common/ebin/"
    ]}]}
].
```

Restart Riak to apply the change.

## Install postcommit hook script

Update the `queue_out.erl` script so that the 2nd line points to the right location of the `amqp_client` module. Install the Erlang environment and compile the script.
```
$ erlc queue_out.erl
```

Place the output file `queue_out.beam` somewhere and add the directory to the `add_paths` key in Riak's `advanced.config` file. Here is an example of the updated file.
```
[
    {riak_kv, [{add_paths, [
        "/Users/guillermo/erlang/beams/amqp_client/ebin/",
        "/Users/guillermo/erlang/beams/rabbit_common/ebin/",
        "/Users/guillermo/erlang/beams/"
    ]}]}
].
```

Restart Riak to apply the change.

## Hook the script to a bucket

Make a `PUT` request to the bucket and add a reference to the module and its main function to the `postcommit` property.
```
$ curl -XPUT -H "Content-Type: application/json" \
        -d '{"props":{"postcommit":[{"mod": "queue_out", "fun": "queue_out"}]}}' \
        http://127.0.0.1:8098/buckets/updates/props
```

Check that the property has been updated.
```
$ curl -s localhost:8098/buckets/updates/props | python -m json.tool
{
    "props": {
        "allow_mult": false,
        "basic_quorum": false,
        "big_vclock": 50,
        "chash_keyfun": {
            "fun": "chash_std_keyfun",
            "mod": "riak_core_util"
        },
        "dvv_enabled": false,
        "dw": "quorum",
        "last_write_wins": false,
        "linkfun": {
            "fun": "mapreduce_linkfun",
            "mod": "riak_kv_wm_link_walker"
        },
        "n_val": 3,
        "name": "updates",
        "notfound_ok": true,
        "old_vclock": 86400,
        "postcommit": [
            {
                "fun": "queue_out",
                "mod": "queue_out"
            }
        ],
        "pr": 0,
        "precommit": [],
        "pw": 0,
        "r": "quorum",
        "rw": "quorum",
        "small_vclock": 50,
        "w": "quorum",
        "young_vclock": 20
    }
}
```

## Declare Rabbit's virtual host and queue

Declare, if they don't exist already, the virtual host and queue in RabbitMQ. You can change the names at the beginning of the `queue_out.erl` file and recompile if you want.
```
$ rabbitmqadmin declare vhost name=/
$ rabbitmqadmin list vhosts
+------+----------+
| name | messages |
+------+----------+
| /    | 0        |
+------+----------+
$ rabbitmqadmin declare queue name=Atlas
$ rabbitmqadmin list queues
+-------------+----------+
|    name     | messages |
+-------------+----------+
| Atlas       | 0        |
+-------------+----------+
```

If you don't have `rabbitmqadmin`, enable the `rabbitmq_management` plugin, and download the `rabbitmqadmin` tool from the very server.
```
$ rabbitmq-plugins enable rabbitmq_management
$ wget http://127.0.0.1:15672/cli/rabbitmqadmin
$ chmod +x rabbitmqadmin
$ mv rabbitmqadmin /usr/local/bin        # optional
```

## Test that everything works

Put an object in Riak and check that it's queued in RabbitMQ.
```
$ curl -XPUT -H 'Content-Type: image/png' http://127.0.0.1:8098/buckets/updates/keys/riak.png --data-binary 'probando'
$ curl http://127.0.0.1:8098/buckets/updates/keys/riak.png
probando
$ rabbitmqadmin list queues
+-------------+----------+
|    name     | messages |
+-------------+----------+
| Atlas       | 1        |
+-------------+----------+
$ rabbitmqadmin get queue=Atlas requeue=false
+-------------+----------+---------------+----------+---------------+------------------+-------------+
| routing_key | exchange | message_count | payload  | payload_bytes | payload_encoding | redelivered |
+-------------+----------+---------------+----------+---------------+------------------+-------------+
| Atlas       |          | 0             | probando | 8             | string           | False       |
+-------------+----------+---------------+----------+---------------+------------------+-------------+
```

# Output side: Node uploader

This is an application in node that listens to the queue and uploads to S3.
