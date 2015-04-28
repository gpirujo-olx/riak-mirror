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

    [
        {riak_kv, [{add_paths, [
            "/Users/guillermo/erlang/beams/amqp_client/ebin/",
            "/Users/guillermo/erlang/beams/rabbit_common/ebin/"
        ]}]}
    ].

Restart Riak to apply the change.

## Install postcommit hook script

Update the `queue_out.erl` script so that the 2nd line points to the right location of the `amqp_client` module. Install the Erlang environment and compile the script.

    $ erlc queue_out.erl

Place the output file `queue_out.beam` somewhere and add the directory to the `add_paths` key in Riak's `advanced.config` file. Here is an example of the updated file.

    [
        {riak_kv, [{add_paths, [
            "/Users/guillermo/erlang/beams/amqp_client/ebin/",
            "/Users/guillermo/erlang/beams/rabbit_common/ebin/",
            "/Users/guillermo/erlang/beams/"
        ]}]}
    ].

Restart Riak to apply the change.

## Hook the script to a bucket

Make a `PUT` request to the bucket and add a reference to the module and its main function to the `postcommit` property.

    $ curl -XPUT -H "Content-Type: application/json" \
           -d '{"props":{"postcommit":[{"mod": "queue_out", "fun": "queue_out"}]}}' \
           http://127.0.0.1:8098/buckets/updates/props

Check that the property has been updated.

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

## Declare Rabbit's virtual host and queue

Declare, if they don't exist already, the virtual host and queue in RabbitMQ. You can change the names at the beginning of the `queue_out.erl` file and recompile if you want.

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

If you don't have `rabbitmqadmin`, enable the `rabbitmq_management` plugin, and download the `rabbitmqadmin` tool from the very server.

    $ rabbitmq-plugins enable rabbitmq_management
    $ wget http://127.0.0.1:15672/cli/rabbitmqadmin
    $ chmod +x rabbitmqadmin
    $ mv rabbitmqadmin /usr/local/bin        # optional

## Test that everything works

Put an object in Riak and check that it's queued in RabbitMQ.

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

# Output side: Node uploader

This is an application in node that listens to the queue and uploads to S3.

## Install required libraries

Dependencies are declared in the `package.json` file and can be automatically installed with `npm`.

    npm install

The libraries used are:

* [Node-AMQP](https://github.com/postwait/node-amqp), a client for Rabbit's AMQP protocol
* [Node-Config](https://github.com/lorenwest/node-config), a configuration file manager
* Amazon's [NodeJS SDK](http://aws.amazon.com/sdk-for-node-js/)


## Adjust the configuration

The scripts comes with a default configuration in the `default.json` file. You can edit the file at your installation and that's it.

If you want to have more configurations, you can create more files with a `.json` extension in the `config` directory. To use them, just set the `NODE_ENV` environment variable to the name of the configuration file. You can find more information about this in the documentation of [the library used](https://github.com/lorenwest/node-config).

## Edit the URL mapping function (optional)

At almost the end of the script, there is a function called `s3Key`. That function returns the S3 key to be used according to the Riak bucket and Riak key it receives as arguments. By default, it returns both values joined with a dash, but you can change it to a different mapping.

## Run the script

Run the script with `node`.

    node uploader.js

You can stop it with `SIGINT` (`Ctrl+C` in console) or `SIGTERM` (a regular `kill`) in any situation. In both cases, the signal is caught by the script and a clean disconnection is performed before termination.

## About reconnection on error

According to the documentation, `node-amqp` automatically tries to reconnect if it loses contact with the server, but I could not reproduce it. If someone wants to give it a try, this is what I've done already.

I tried to test it by turning RabbitMQ off, and the node script just terminates. Perhaps turning the server off cleanly makes a clean disconnection and that's why it doesn't try to reconnect, but I cannot tell.

I added the following snippet to capture all events emitted by the connection.

    var oldEmit = connection.emit;
    connection.emit = function() {
        console.log(arguments);
        oldEmit.apply(connection, arguments);
    };

There are an `end` event and a `close` event when the server shuts down, but that also happens when there is a connection error, and therefore I cannot tell when the error is final. You can also enable debug messages in the library by setting the `NODE_DEBUG_AMQP` environment variable to something true.
 
    NODE_DEBUG_AMQP=1 node uploader.js

That spits a lot of debug messages, but I found nothing useful there.