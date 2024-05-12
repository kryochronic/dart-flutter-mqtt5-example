/* 
Author at [at] kryochronic.me, 2024
LICENSE: MIT.

This is a simple example of using the mqtt5_client package to 
connect to a Mosquitto broker using a Secure WebSocket and 
AWS IoT Core with Certificates. Most of the examples are set on
JS / Python / Java so I hope this helps some one.

All you'll need is to have the certificates in the assets/cert folder
and the update the configs section below.
If time permits, and as per need I'll enhance this to a
full fledged example on a MacOS.

*/
import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';

import 'package:mqtt5_client/mqtt5_client.dart';
import 'package:mqtt5_client/mqtt5_server_client.dart';


/* CONFIGS >>> Start */
// wget https://www.amazontrust.com/repository/AmazonRootCA1.pem > assets/cert/AmazonRootCA1.pem
final strrootCA = 'assets/cert/root-CA.crt';
final pub_key = 'assets/cert/xxx.cert.pem';
final strprivKey = 'assets/cert/xxx.private.key';

final mqtt_endpoint = 'xxxxxxxxxxxxxx';
final mqtt_port = 8883;
final mqtt_clientIdentifier = 'xxx';
final mqtt_topic = 'xxx';
/* CONFIGS >>> End */


final client = MqttServerClient.withPort(mqtt_endpoint,mqtt_clientIdentifier, mqtt_port);


Future<int> main() async {
    // runApp();
    // Only for macOS
    // convert to chained pfx
    // openssl pkcs12 -export -out vdb_app_001.private.p12 -inkey vdb_app_001.private.key -in vdb_app_001.cert.pem -certfile root-CA.crt
    
    // Convert crt to pem
    // openssl x509 -in root-CA.crt -out root-CA.crt.pem 
    
    // Convert to DER format
    // openssl x509 -outform der -in vdb_app_001.cert.pem -out vdb_app_001.cert.der  
    // openssl x509 -in root-CA.crt -out root-CA.crt.pem 

    WidgetsFlutterBinding.ensureInitialized();


    final rootCA = await rootBundle.load(strrootCA);
    final certificates = await rootBundle.load(pub_key);
    final privateKey = await rootBundle.load(strprivKey);

    SecurityContext context = new SecurityContext()
    ..setTrustedCertificatesBytes(rootCA.buffer.asUint8List())
    ..useCertificateChainBytes(certificates.buffer.asUint8List())
    ..usePrivateKeyBytes(privateKey.buffer.asUint8List());
    
    runApp(MyApp());

    client.secure = true;
    client.securityContext = context;
    
    client.useWebSocket = true;
    client.port = 8883;

    // client.port = 443; // ( needs 8883 for websocket )
    /// You can also supply your own websocket protocol list or disable this feature using the websocketProtocols
    /// setter, read the API docs for further details here, the vast majority of brokers will support the client default
    /// list so in most cases you can ignore this.
    /// client.websocketProtocols = ['myString'];

    /// Set logging on if needed, defaults to off
    client.logging(on: true);

    /// If you intend to use a keep alive value in your connect message that is not the default(60s)
    /// you must set it here
    client.keepAlivePeriod = 20;

    /// Add the unsolicited disconnection callback
    client.onDisconnected = onDisconnected;

    /// Add the successful connection callback
    client.onConnected = onConnected;

    /// Add a subscribed callback, there is also an unsubscribed callback if you need it.
    /// You can add these before connection or change them dynamically after connection if
    /// you wish. There is also an onSubscribeFail callback for failed subscriptions, these
    /// can fail either because you have tried to subscribe to an invalid topic or the broker
    /// rejects the subscribe request.
    client.onSubscribed = onSubscribed;

    /// Set a ping received callback if needed, called whenever a ping response(pong) is received
    /// from the broker.
    client.pongCallback = pong;
    // client.onData = onData;




    /// Create a connection message to use or use the default one. The default one sets the
    /// client identifier, any supplied username/password, the default keepalive interval(60s)
    /// and clean session, an example of a specific one below.
    /// Add some user properties, these may be available in the connect acknowledgement.
    /// Note there are many options selectable on this message, if you opt to use authentication please see
    /// the example in mqtt5_server_client_authenticate.dart.
    final property = MqttUserProperty();
    property.pairName = 'senderName';
    property.pairValue = 'at@kryochronic.me';
    final connMess = MqttConnectMessage()
        .withClientIdentifier('${mqtt_clientIdentifier}')
        .startClean() // Or startSession() for a persistent session
        // .startSession()
        .withUserProperties([property]);
    print('EXAMPLE::Mosquitto client connecting....');
    client.connectionMessage = connMess;

    /// Connect the client, any errors here are communicated by raising of the appropriate exception. Note
    /// in some circumstances the broker will just disconnect us, see the spec about this, we however will
    /// never send malformed messages.
    try {
      await client.connect();
    } on MqttNoConnectionException catch (e) {
      // Raised by the client when connection fails.
      print('EXAMPLE::MqttNoConnectionException::client exception - $e');
      client.disconnect();
    } on SocketException catch (e) {
      // Raised by the socket layer
      print('EXAMPLE::SocketException::socket exception - $e');
      client.disconnect();
    }

    /// Check we are connected
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('EXAMPLE::Mosquitto client connected');
    } else {
      /// Use status here rather than state if you also want the broker return code.
      print(
          'EXAMPLE::ERROR Mosquitto client connection failed - disconnecting, status is ${client.connectionStatus}');
      client.disconnect();
      exit(-1);
    }

    /// Ok, lets try a subscription
    print('EXAMPLE::Subscribing to the ${mqtt_topic} topic');
    final topic = '${mqtt_topic}'; // Not a wildcard topic
    client.subscribe(topic, MqttQos.atMostOnce);

    /// The client has a change notifier object(see the Observable class) which we then listen to to get
    /// notifications of published updates to each subscribed topic.
    client.updates.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt = MqttUtilities.bytesToStringAsString(recMess.payload.message!);

      /// The above may seem a little convoluted for users only interested in the
      /// payload, some users however may be interested in the received publish message,
      /// lets not constrain ourselves yet until the package has been in the wild
      /// for a while.
      /// The payload is a byte buffer, this will be specific to the topic
      print(
          'EXAMPLE::Change notification:: topic is <${c[0].topic}>, payload is <-- $pt -->');
      print('');
    });

    /// If needed you can listen for published messages that have completed the publishing
    /// handshake which is Qos dependant. Any message received on this stream has completed its
    /// publishing handshake with the broker.
    client.published!.listen((MqttPublishMessage message) {
      print(
          'EXAMPLE::Published notification:: topic is ${message.variableHeader!.topicName}, with Qos ${message.header!.qos}');
    });

    /// Lets publish to our topic
    /// Use the payload builder rather than a raw buffer
    /// Our known topic to publish to
    final pubTopic = mqtt_topic;
    final builder = MqttPayloadBuilder();
    builder.addString('Hello from ${mqtt_clientIdentifier}');

    /// Subscribe to it
    print('EXAMPLE::Subscribing to the topic:"**${mqtt_topic}**"');
    client.subscribe(pubTopic, MqttQos.atLeastOnce);

    /// Publish it
    print('EXAMPLE::Publishing our topic');
    client.publishMessage(pubTopic, MqttQos.atLeastOnce, builder.payload!);

    /// Ok, we will now sleep a while, in this gap you will see ping request/response
    /// messages being exchanged by the keep alive mechanism.
    print('EXAMPLE::Sleeping....');
    await MqttUtilities.asyncSleep(120);

    /// Finally, unsubscribe and exit gracefully
    print('EXAMPLE::Unsubscribing');
    client.unsubscribeStringTopic(topic);

    /// Wait for the unsubscribe message from the broker if you wish.
    await MqttUtilities.asyncSleep(2);
    print('EXAMPLE::Disconnecting');
    client.disconnect();
    return 0;
}

void onData(List<MqttReceivedMessage<MqttMessage>> data) {
  print('Received message:${data[0].toString()}');
}

/// The subscribed callback
void onSubscribed(MqttSubscription subs) {
  print('EXAMPLE::Subscription confirmed for topic ${subs.topic}');
}

/// The unsolicited disconnect callback
void onDisconnected() {
  print('EXAMPLE::OnDisconnected client callback - Client disconnection');
  if (client.connectionStatus!.disconnectionOrigin ==
      MqttDisconnectionOrigin.solicited) {
    print('EXAMPLE::OnDisconnected callback is solicited, this is correct');
  }
  exit(-1);
}

/// The successful connect callback
void onConnected() {
  print(
      'EXAMPLE::OnConnected client callback - Client connection was sucessful');
}

/// Pong callback
void pong() {
  print('EXAMPLE::Ping response client callback invoked');
}

// void main() {
//   runApp(MyApp());
//   connectDoorbellMQTT();
// }


connectDoorbellMQTT() async {
  final certificates = await rootBundle.load('assets/cert/doorbell.crt.pem');
  final privateKey = await rootBundle.load('assets/cert/doorbell_private.key');
  final authorities = await rootBundle.load('assets/cert/doorbell.crt');
  MqttServerClient client = MqttServerClient.withPort(
      'a39228zqnk50o8-ats.iot.ap-south-1.amazonaws.com', 'sdk-nodejs-v2', 443,
      maxConnectionAttempts: 3);
  SecurityContext context = new SecurityContext()
    ..setTrustedCertificatesBytes(authorities.buffer.asUint8List())
    ..usePrivateKeyBytes(privateKey.buffer.asUint8List())
    ..setClientAuthoritiesBytes(certificates.buffer.asUint8List());
  client.secure = true;
  client.securityContext = context;
  // client.setProtocolV311();
  client.onConnected = onConnected;
  // client.onBadCertificate = (Object obj) {
  //   print(obj);
  //   return false;
  // };
  // try {
  //   await client.connect().timeout(Duration(seconds: 60));
  // } catch (e) {
  //   print('Exception: $e');
  //   client.disconnect();
  // }
}

// void onConnected() {
//   print('----- mqtt client connected successfully-----');
// }

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
