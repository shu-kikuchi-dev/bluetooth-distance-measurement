import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_test1/CalcRSSI.dart';
import 'package:flutter_blue_plus_test1/CalcDistance.dart';

//パーミッションリクエスト用パッケージ
import 'package:permission_handler/permission_handler.dart';


// default
void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: BluetoothScanner(),
    );
  }
}

// ---BluetoothScanner Widget---
class BluetoothScanner extends StatefulWidget {
  @override
  _BluetoothScannerState createState() => _BluetoothScannerState();
}

class _BluetoothScannerState extends State<BluetoothScanner> {
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  String _connectionStatus = '';
  //bool型のすべてのデバイスを含むマップを作ることで、個々のデバイス全てで接続状態が共有されることを防ぐ
  final Map<BluetoothDevice, bool> _connectedDevices = {};
  final RSSICalculator _rssiCalculator = RSSICalculator();

  //デバイス名、txPowerの一括管理
  final Map<BluetoothDevice, String> _deviceNames = {};
  final Map<BluetoothDevice, int?> _txPowers = {};

  @override
  void initState() {
    super.initState();

    //Android13以降で必要なランタイムパーミッションリクエスト関数の呼び出し
    //_requestPermissions();

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        //txPower取得できる機器だけ表示したいとき
        _scanResults = results.where((result) {
          return result.advertisementData.txPowerLevel != null;
        }).toList();
        //_scanResults = results.toList(); //txPower取得できない機器も表示したいとき
      });
    });
  }

  //ランタイムパーミッションリクエスト
  Future<void> _requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothAdvertise.request();
    await Permission.location.request();
  }

  //スキャン開始
  void startScan() async {
    if (!_isScanning) {
      setState(() {
        _isScanning = true;
        _scanResults = [];
      });
      await FlutterBluePlus.startScan(timeout: Duration(seconds: 3));
    }
    else {
      await FlutterBluePlus.stopScan();
      setState(() {
        _isScanning = false;
      });
    }

    //3秒たったらもう一度スキャンする
    Future.delayed(const Duration(seconds: 3), () {
      if(_isScanning) {
        FlutterBluePlus.stopScan();
        startScan();
      }
    });
  }

  //接続
  Future<void> _connectDevice(BluetoothDevice device, {int attempt = 0, int maxAttempts = 2}) async {
    String deviceName = _deviceNames[device]!;

    setState(() {
      _connectionStatus = 'Now connecting... to $deviceName';
    });

    try {
      await device.connect();
      device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.connected) {
          print('Connected to $deviceName');
          setState(() {
            _connectedDevices[device] = true;
            _connectionStatus = 'Connected to $deviceName!';
          });

          //サービス取得関数呼び出し
          _discoverServices(device); //サービス発見まではいいが、その後の処理の成功率が異様に低い

          //デバイス情報表示関数呼び出し
          _showDeviceInfoWidget(device);
        }
        else if (state == BluetoothConnectionState.disconnected) {
          print('Disconnected from $deviceName');
          setState(() {
            _connectedDevices[device] = false;
            _connectionStatus = 'Disconnected from $deviceName';
          });
        }
      });
    }
    catch (e) {
      print('Error connecting failed, retrying...');
      setState(() {
        _connectionStatus = 'Connection failed, retrying... to connect to $deviceName';
      });

      if (attempt < maxAttempts) {
        Future.delayed(const Duration(seconds: 1), () {
          print('Retrying to connect: attempt ${attempt + 1}');
          _connectDevice(device, attempt: attempt + 1, maxAttempts: maxAttempts);
        });
      }
      else {
        print('Failed to connect to $deviceName after $maxAttempts attempts.');
        setState(() {
          _connectionStatus = 'Connecting to $deviceName failed after $maxAttempts attempts';
        });
        _showConnectionFailedDialog(device);
      }
    }
  }

  //サービス発見
  Future<void> _discoverServices(BluetoothDevice device) async {
    setState(() {
      _connectionStatus = 'Discovering services...';
    });

    List<BluetoothService> services = await device.discoverServices();
    setState(() {
      _connectionStatus = 'Service discovered';
    });

    //デバイス情報サービスの発見
    BluetoothService? deviceInfoService = services.firstWhere(
            (service) =>service.uuid.toString() == '0000180a-0000-1000-8000-00805f9b34fb' || service.uuid.toString() == '180a',
        orElse: () => null as BluetoothService
    );

    if (deviceInfoService != null) {
      //名前特性
      BluetoothCharacteristic? deviceNameCharacteristic = deviceInfoService.characteristics.firstWhere(
              (characteristic) => characteristic.uuid.toString == '00002a00-0000-1000-8000-00805f9b34fb' || characteristic.uuid.toString() == '2a00',
          orElse: () => null as BluetoothCharacteristic
      );

      if (deviceNameCharacteristic != null) {
        List<int> deviceNameData = await deviceNameCharacteristic.read();
        String deviceNameFromCharacteristic = utf8.decode(deviceNameData);

        setState(() {
          _connectionStatus = 'Device Name: $deviceNameFromCharacteristic';
        });
        print('Device Name from characteristic: $deviceNameFromCharacteristic');

        _deviceNames[device] = deviceNameFromCharacteristic; //デバイス名更新
      }
      else {
        setState(() {
          _connectionStatus = 'Device Name characteristic not found';
        });
        print('Device Name characteristic not found');
      }

      //txPower特性
      BluetoothCharacteristic txPowerCharacteristic = deviceInfoService.characteristics.firstWhere(
              (characteristic) => characteristic.uuid.toString() == '00002a07-0000-1000-8000-00805f9b34fb',
          orElse: () => null as BluetoothCharacteristic
      );

      if (txPowerCharacteristic != null) {
        List<int> txPowerData = await txPowerCharacteristic.read();
        int txPowerFromCharacteristic = txPowerData[0]; //txPowerは特性の最初のバイト

        _txPowers[device] = txPowerFromCharacteristic; //txPower更新
      }
      else {
        print('TxPower value not found');
      }
    }
  }

  //接続失敗ポップアップ
  void _showConnectionFailedDialog(BluetoothDevice device) {
    String deviceName = _deviceNames[device]!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Connection Failed'),
        content: Text('Failed to connect to $deviceName after multiple attempts.'),
        actions: [
          TextButton(
            child: Text('OK'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  //デバイス情報表示（接続成功時）
  void _showDeviceInfoWidget(BluetoothDevice device) {
    String deviceName = _deviceNames[device]!;
    int txPower = _txPowers[device]!;

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    final scanResult = _scanResults.firstWhere((result) => result.device.remoteId == device.remoteId);
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => DeviceInfoWidget(
        device: device,
        deviceName: deviceName,
        scanResult: scanResult,
        txPower: txPower,
        onDisconnect: () async {
          await device.disconnect();
          _connectedDevices[device] = false;
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bluetooth Scanner'),
      ),
      body: Column(
        children: [
          ElevatedButton(
            onPressed: startScan,
            child: Text(_isScanning ? 'Stop Scan' : 'Start Scan'),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(_connectionStatus, style: TextStyle(fontSize: 18)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _scanResults.length,
              itemBuilder: (context, index) {
                final result = _scanResults[index];
                final device = result.device;
                final advertisementData = result.advertisementData;

                //デバイス名取得
                final manufactureData = advertisementData.manufacturerData;
                final customName = manufactureData.isNotEmpty? utf8.decode(manufactureData.values.first, allowMalformed: true) : null;
                final deviceName = advertisementData.advName?.isNotEmpty == true
                    ? advertisementData.advName : device.platformName.isNotEmpty
                    ? device.platformName : customName ?? 'Unknown Device';
                //デバイス名をマップに保存
                if (!_deviceNames.containsKey(device)) {
                  _deviceNames[device] = deviceName;
                }

                //RSSIとTxPowerの取得
                final rssi = _rssiCalculator.formatRSSI(result.rssi);
                final txPower = result.advertisementData.txPowerLevel;
                //txPowerをマップに保存
                if (!_txPowers.containsKey(device)) {
                  _txPowers[device] = txPower;
                }

                //デバイスごとの接続状態を初期化
                if (!_connectedDevices.containsKey(device)) {
                  _connectedDevices[device] = false;
                }

                return ListTile(
                  title: Text(deviceName),
                  subtitle: Text('Id: ${device.remoteId}\nRSSI: $rssi [dBm]\nTxPower: $txPower [dBm]'),
                  trailing: ElevatedButton(
                    onPressed: () async {
                      try {
                        await _connectDevice(device);
                      }
                      catch (e) {
                        print('Error connecting to device: $e');
                      }
                    },
                    child: Text(_connectedDevices[device]! ? 'Connected!!' : 'Connect'),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---DeviceInfo Widget---
class DeviceInfoWidget extends StatefulWidget {
  final BluetoothDevice device;
  final String deviceName;
  final ScanResult scanResult;
  final int txPower;
  final Function onDisconnect;

  const DeviceInfoWidget({
    Key? key,
    required this.device,
    required this.deviceName,
    required this.scanResult,
    required this.txPower,
    required this.onDisconnect,
  }) : super(key: key);

  @override
  _DeviceInfoWidgetState createState() => _DeviceInfoWidgetState();
}

class _DeviceInfoWidgetState extends State<DeviceInfoWidget> {
  int? _rssi;
  int? _txPower;
  double? _distance;
  final RSSICalculator _rssiCalculator = RSSICalculator();

  @override
  void initState() {

    super.initState();
    _txPower = widget.txPower;
    _rssiCalculator.startRssiStream(widget.device, (rssi) {
      setState(() {
        _rssi = rssi;
        _distance = DistanceCalculator.calculateDistance(_txPower, _rssi);
      });
    });
    _calculateDistance();
  }

  void _calculateDistance() {
    if (_rssi != null && _txPower != null) {
      _distance = DistanceCalculator.calculateDistance(_txPower!, _rssi!);
      setState(() {});//ウィジェットを再描写しているだけ
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text('Device: ${widget.deviceName}'),
            Text('RSSI: $_rssi [dBm]'),
            Text('TxPower: $_txPower [dBm]'),
            Text('Distance: ${_distance?.toStringAsFixed(2)} [m]'),
            ElevatedButton(
              onPressed: () => widget.onDisconnect(),
              child: Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}