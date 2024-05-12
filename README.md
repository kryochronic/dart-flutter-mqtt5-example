# A MacOS Flutter Client for the AWS IoT using Secure WebSocket

A MacOS Flutter Client for the AWS IoT using Secure WebSocket for a Project utilising the AWS IoT Ecosystem

## Getting Started

### Setup Auth
Grab the Credentials and place them in the `assets/sert` forlder.

```shell
mkdir -p assets/cert
if [ ! -f ./assets/cert/root-CA.crt ]; then
  printf "\nDownloading AWS IoT Root CA certificate from AWS...\n"
  curl https://www.amazontrust.com/repository/AmazonRootCA1.pem > ./assets/cert/root-CA.crt
fi
```

### Setup `assets` in `pubspec.yaml`

In the `pubspec.yaml` make sure the certificates are listed in the `flutter/assets` section as follows

```yaml
flutter:
  assets:
    - assets/cert/root-CA.crt
    - assets/cert/xxx.cert.pem
    - assets/cert/xxx.private.key
```

### Setup the Configs in `lib/main.dart`

Open the `lib/main.dart` and configure the follwing:

```dart
final strrootCA = 'assets/cert/root-CA.crt';
final pub_key = 'assets/cert/xxx.cert.pem';
final strprivKey = 'assets/cert/xxx.private.key';

final mqtt_endpoint = 'xxxxxxxxxxxxxx';
final mqtt_port = 8883; // AWS IoT Core uses poty 8883 for mqtt protocol.
final mqtt_clientIdentifier = 'xxx';
final mqtt_topic = 'xxx';
```


### Fire it up

```shell
flutter clean
flutter pub get
flutter build macos
```

And then 
```shell
flutter run
```

and select the option `macOS`.

### TLS VERIFY Errors / RootCA ?

AWS self-signs their certificates which isn't trusted out of the box.
We explicitly set the security context to trust the rootCA's certificate via `setTrustedCertificatesBytes`.

Excerpt from `lib/main.dart` below:

```dart
SecurityContext context = new SecurityContext()
    ..setTrustedCertificatesBytes(rootCA.buffer.asUint8List())
    ..useCertificateChainBytes(certificates.buffer.asUint8List())
    ..usePrivateKeyBytes(privateKey.buffer.asUint8List());
```


---

##### END OF DOCUMENT