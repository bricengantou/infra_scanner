import 'dart:async';
import 'package:flutter/services.dart';

/// Modes d’output du SDK
enum ScanOutMode { broadcast, editBox, keyboard }

class BarcodeEvent {
  final String code;
  final int length;
  final String barcodeType;
  final String aimId;
  final List<int> raw;

  BarcodeEvent({
    required this.code,
    required this.length,
    required this.barcodeType,
    required this.aimId,
    required this.raw,
  });

  factory BarcodeEvent.fromMap(Map<dynamic, dynamic> m) {
    return BarcodeEvent(
      code: (m['code'] ?? '') as String,
      length: (m['length'] ?? 0) as int,
      barcodeType: (m['barcodeType'] ?? '') as String,
      aimId: (m['aimId'] ?? '') as String,
      raw: (m['raw'] as List<dynamic>? ?? const []).cast<int>(),
    );
  }
}

class InfraScanner {
  InfraScanner._();
  static final InfraScanner instance = InfraScanner._();

  static const MethodChannel _m = MethodChannel('com.linnovlab/infra_scanner');
  static const EventChannel _e =
      EventChannel('com.linnovlab/infra_scanner/scanStream');

  Stream<BarcodeEvent>? _stream;

  /// Flux des scans (mode broadcast requis côté SDK)  :contentReference[oaicite:8]{index=8}
  Stream<BarcodeEvent> get onScan {
    _stream ??=
        _e.receiveBroadcastStream().map((e) => BarcodeEvent.fromMap(e as Map));
    return _stream!;
  }

  Future<bool> isScanOpened() async =>
      (await _m.invokeMethod('isScanOpened')) as bool;
  Future<bool> open() async => (await _m.invokeMethod('openScan')) as bool;
  Future<bool> close() async => (await _m.invokeMethod('closeScan')) as bool;
  Future<bool> start() async => (await _m.invokeMethod('startScan')) as bool;
  Future<bool> stop() async => (await _m.invokeMethod('stopScan')) as bool;
  Future<bool> reset() async => (await _m.invokeMethod('resetScan')) as bool;

  /// Active/désactive le scan continu (4 = ON, 8 = OFF côté SDK)  :contentReference[oaicite:9]{index=9}
  Future<void> setContinuous({required bool on}) async =>
      _m.invokeMethod('setContinuous', {'on': on});

  /// 0 = broadcast | 1 = editBox | 2 = keyboard  :contentReference[oaicite:10]{index=10}
  Future<bool> setOutScanMode(ScanOutMode mode) async =>
      (await _m.invokeMethod('setOutScanMode', {'mode': mode.index})) as bool;

  Future<int> getOutScanMode() async =>
      (await _m.invokeMethod('getOutScanMode')) as int;
}
