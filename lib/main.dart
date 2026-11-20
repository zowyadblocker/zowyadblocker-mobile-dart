import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app/screens.dart';
import 'services/vpn_runtime.dart' as runtime;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Shizuku API/provider',
    ], await rootBundle.loadString('docs/licenses/Shizuku-LICENSE.txt'));
  });
  runApp(const ZowyApp());
}

@pragma('vm:entry-point')
Future<void> vpnMain() => runtime.vpnMain();
@pragma('vm:entry-point')
Future<void> filterUpdateMain() => runtime.filterUpdateMain();
