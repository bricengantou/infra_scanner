import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/services.dart';
import 'package:infra_scanner/infra_scanner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('open/close smoke', (tester) async {
    // Tente d'ouvrir le scanner. Si le SDK n'est pas dispo (émulateur),
    // le plugin peut renvoyer PlatformException(code: NO_SDK) → on accepte.
    String outcome = 'unknown';
    try {
      final opened = await InfraScanner.instance.open();
      expect(opened, isA<bool>());
      await InfraScanner.instance.setOutScanMode(ScanOutMode.broadcast);
      await InfraScanner.instance.close();
      outcome = 'ok';
    } on PlatformException catch (e) {
      if (e.code == 'NO_SDK') {
        outcome = 'nosdk';
      } else {
        rethrow;
      }
    }
    expect(['ok', 'nosdk'].contains(outcome), true);
  });
}
