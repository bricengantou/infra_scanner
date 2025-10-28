import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:infra_scanner/infra_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InfraScanner – mapping', () {
    test('BarcodeEvent.fromMap', () {
      final e = BarcodeEvent.fromMap({
        'code': '1234567890123',
        'length': 13,
        'barcodeType': 'EAN13',
        'aimId': ']E0',
        'raw': [0x31, 0x32, 0x33],
      });
      expect(e.code, '1234567890123');
      expect(e.length, 13);
      expect(e.barcodeType, 'EAN13');
      expect(e.aimId, ']E0');
      expect(e.raw, isA<List<int>>());
    });
  });

  group('InfraScanner – MethodChannel', () {
    const MethodChannel ch = MethodChannel('com.linnovlab/infra_scanner');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, (call) async {
        switch (call.method) {
          case 'getOutScanMode':
            return 0;
          case 'openScan':
            return true;
          case 'closeScan':
            return true;
          case 'startScan':
            return true;
          case 'stopScan':
            return true;
          case 'resetScan':
            return true;
          case 'setOutScanMode':
            return true;
          case 'isScanOpened':
            return true;
          case 'setContinuous':
            return null;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ch, null);
    });

    test('getOutScanMode returns 0', () async {
      final v = await InfraScanner.instance.getOutScanMode();
      expect(v, 0);
    });
  });
}
