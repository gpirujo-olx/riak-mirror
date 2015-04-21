//
// RABBIT SIDE
// 

function listenToRabbit(connection, queue) {
    return function(callback) {
        var amqp = require('amqp');
        var connection = amqp.createConnection(connection);

        // Disconnect cleanly upon Ctrl-C or SIGTERM
        function closeConnection() {
            console.log('Disconnecting...');
            connection.disconnect();
        }
        process.on('SIGINT', closeConnection);
        process.on('SIGTERM', closeConnection);

        connection.on('ready', function() {
            connection.queue(queue, {
                durable: true,
                autoDelete: false
            }, function (queue) {
                queue.bind('#');
                queue.subscribe(callback);
                console.log('Waiting for messages...');
            });
        });

        console.log('Connecting...');
        connection.connect();
    };
}

//
// S3 SIDE
//

function connectToAmazon(bucket, listenToQueue, s3Key) {
    var AWS = require('aws-sdk');
    var s3 = new AWS.S3();
    listenToQueue(function(message, headers) {
        var key = s3Key(headers['X-Bucket'], headers['X-Key']);
        if (headers['X-Deleted'] === 'true') {

            s3.deleteObject({
                Bucket: s.bucket,
                Key: key,
            }, function(err, data) {
                if (err) console.log(err);
                else console.log("Successfully deleted " + key);
            });

        } else {

            s3.putObject({
                Bucket: s.bucket,
                Key: key,
                ContentType: message.contentType,
                Body: message.data,
            }, function(err, data) {
                if (err) console.log(err);
                else console.log("Successfully uploaded " + key);
            });

        }
    });
}

//
// GO!
//

function s3Key(riakBucket, riakKey) {
    return riakBucket + '_' + riakKey;
}

var config = require('config');
var q = config.get('queue');
var s = config.get('s3');
connectToAmazon(
    s.bucket,
    listenToRabbit(
        {
            host: q.host,
            port: q.port,
            login: q.login,
            password: q.password,
            vhost: q.vhost,
        },
        q.queue
    ),
    s3Key
);
