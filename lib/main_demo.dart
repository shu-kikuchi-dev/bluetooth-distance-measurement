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
  //bool型のすべてのデバイスを含むマップを作ることで、全体で接続状態が共有されることを防ぐ
  final Map<BluetoothDevice, bool> _connectedDevices = {};
  final RSSICalculator _rssiCalculator = RSSICalculator();

  //仮定名称・TxPowerのためにクラス全体で宣言する
  int fixedTxPower = 0;
  String fixedDeviceName ='';
  final Map<BluetoothDevice, DeviceInfo> _deviceInfos = {};

  @override
  void initState() {
    super.initState();

    //Android13以降で必要なランタイムパーミッションリクエスト関数の呼び出し
    _requestPermissions();

    //以下仮定名称・TxPower
    int minName = 0;
    int maxName = 9;

    int minTx = -70;
    int maxTx = -59;

    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        _scanResults = results.where((result) {
          return result.advertisementData.txPowerLevel != null;
        }).toList();
        //_scanResults = results.toList(); txPowerない機器も表示したいとき
      });

      //リザルトごとに仮定の名称を割り当て（なぜか名称とTxPowerが取得できない）
      for (var result in _scanResults) {
        if (!_deviceInfos.containsKey(result.device)) {
          _deviceInfos[result.device] = DeviceInfo(
              fixedDeviceName: 'Device_${minName + Random().nextInt(maxName - minName + 1)}',
              fixedTxPower: minTx + Random().nextInt(maxTx - minTx + 1)
          );
        }
      }
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
  Future<void> _connectDevice(BluetoothDevice device, String deviceName, {int attempt = 0, int maxAttempts = 2}) async {
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

          _showDeviceInfoWidget(device, deviceName);
          //_discoverServices(device, deviceName); サービス発見まではいいが、その後の処理の成功率が異様に低いのでオミット
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
          _connectDevice(device, deviceName, attempt: attempt + 1, maxAttempts: maxAttempts);
        });
      }
      else {
        print('Failed to connect to $deviceName after $maxAttempts attempts.');
        setState(() {
          _connectionStatus = 'Connecting to $deviceName failed after $maxAttempts attempts';
        });
        _showConnectionFailedDialog(deviceName);
      }
    }
  }

  //サービス発見
  Future<void> _discoverServices(BluetoothDevice device, String deviceName) async {
    setState(() {
      _connectionStatus = 'Discovering services...';
    });

    List<BluetoothService> services = await device.discoverServices();
    setState(() {
      _connectionStatus = 'Service discovered';
    });

    //デバイス情報サービスの発見
    BluetoothService? deviceInfoService = services.firstWhere(
            (service) => service.uuid == Guid('0000180a-0000-1000-8000-00805f9b34fb'), orElse: () => null as BluetoothService
    );

    if (deviceInfoService != null) {
      BluetoothCharacteristic? deviceNameCharacteristic = deviceInfoService.characteristics.firstWhere(
              (characteristic) => characteristic.uuid == Guid('00002a00-0000-1000-8000-00805f9b34fb'), orElse: () => null as BluetoothCharacteristic
      );

      if (deviceNameCharacteristic != null) {
        List<int> deviceNameData = await deviceNameCharacteristic.read();
        String deviceNameFromCharacteristic = utf8.decode(deviceNameData);

        setState(() {
          _connectionStatus = 'Device Name: $deviceNameFromCharacteristic';
        });
        print('Device Name from characteristic: $deviceNameFromCharacteristic');

        //名前特性発見後、名前が発見されたら、ここにdeviceNameを更新するような処理を書きたい
        // deviceNameをBluetoothScannerStateクラス全体で宣言し、他クラスで引用時、BluetoothScannerStateクラスのインスタンスを作ればアクセス可能
      }
      else {
        setState(() {
          _connectionStatus = 'Device Name characteristic not found';
        });
        print('Device Name characteristic not found');
      }
    }
  }

  //接続失敗ポップアップ
  void _showConnectionFailedDialog(String deviceName) {
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
  void _showDeviceInfoWidget(BluetoothDevice device, String deviceName) {
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
        fixedDeviceName: _deviceInfos[device]!.fixedDeviceName,//仮定名称
        fixedTxPower: _deviceInfos[device]!.fixedTxPower,//仮定TxPower
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
                /*仮定名称使用のためコメント化
                final manufactureData = advertisementData.manufacturerData;
                final customName = manufactureData.isNotEmpty? utf8.decode(manufactureData.values.first, allowMalformed: true) : null;
                final deviceName = advertisementData.advName?.isNotEmpty == true
                    ? advertisementData.advName : device.platformName.isNotEmpty
                        ? device.platformName : customName ?? 'Unknown Device';*/

                //仮定名称、仮定TxPower割り当て
                final deviceInfo = _deviceInfos[device];
                final deviceName = deviceInfo!.fixedDeviceName;
                final txPower = deviceInfo!.fixedTxPower;

                //RSSIとTxPowerの取得
                final rssi = _rssiCalculator.formatRSSI(result.rssi);
                //final txPower = result.advertisementData.txPowerLevel; 仮定TxPower取得のためコメント化

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
                        await _connectDevice(device, deviceName);
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
  final Function onDisconnect;

  //仮定名称・TxPower定義
  final int fixedTxPower;
  final String fixedDeviceName;

  const DeviceInfoWidget({
    Key? key,
    required this.device,
    required this.deviceName,
    required this.scanResult,
    required this.onDisconnect,

    //必要引数に仮定名称・TxPowerを指定
    required this.fixedDeviceName,
    required this.fixedTxPower,
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
    //_txPower = widget.scanResult.advertisementData.txPowerLevel; 仮定データ利用のためコメント化
    _rssiCalculator.startRssiStream(widget.device, (rssi) {
      setState(() {
        _rssi = rssi;
        _txPower = widget.fixedTxPower; //仮定TxPower
        _distance = DistanceCalculator.calculateDistance(_txPower, _rssi);
      });
    });
    _calculateDistance();
  }

  void _calculateDistance() {
    if (_rssi != null && _txPower != null) {
      _txPower = widget.fixedTxPower; //仮定TxPower
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
            Text('Device: ${widget.fixedDeviceName}'),
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

//仮定名称・TxPower管理用クラス
class DeviceInfo {
  final int fixedTxPower;
  final String fixedDeviceName;

  DeviceInfo({required this.fixedDeviceName, required this.fixedTxPower});
}