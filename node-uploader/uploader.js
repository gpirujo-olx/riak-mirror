var amqp = require('amqp');
var util = require('util');

var connection = amqp.createConnection({
    host: 'localhost',
    port: 5672,
    login: 'guest',
    password: 'guest',
    vhost: '/'
});

// Wait for connection to become established.
connection.on('ready', function () {

    connection.exchange('', {
        type: 'fanout'
    }, function(exchange) {

        // Use the default 'amq.topic' exchange
        connection.queue('Atlas', {
            durable: true,
            autoDelete: false
        }, function (q) {

            // Catch all messages
            q.bind('#');

            console.log('Waiting for messages...');

            // Receive messages
            q.subscribe(function (message, headers) {

                // Print messages to stdout
                console.log(util.inspect(message));
                console.log(util.inspect(headers));

            });

        });

    });

});

connection.connect();
