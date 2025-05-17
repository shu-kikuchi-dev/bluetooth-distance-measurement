import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class RSSICalculator {
  int? _lastRssi;

  void startRssiStream(BluetoothDevice device, Function callback) {
    device.readRssi().then((value) {
      _lastRssi = value;
      callback(value);
    });

    //定期的にRSSIを更新
    Timer.periodic(Duration(seconds: 1), (timer) {
      device.readRssi().then((value) {
        _lastRssi = value;
        callback(value);
      });
    });
  }

  String formatRSSI(int rssi) {
    return '$rssi';
  }

  int? get lastRssi => _lastRssi;
}