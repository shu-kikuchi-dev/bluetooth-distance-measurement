import 'package:flutter/material.dart';
import "dart:math";

class DistanceCalculator {
  static double calculateDistance(int? txPower, int? rssi, {double pathLossExponent = 2.0}) {
    if (txPower == null || rssi == null) {
      throw ArgumentError('TxPower and RSSI must not be null');
    }

    double distance = pow(10, (txPower - rssi) / (10 * pathLossExponent)).toDouble();
    return distance;
  }
}