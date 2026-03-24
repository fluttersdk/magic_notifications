import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

/// Initialize Magic framework for tests.
///
/// Call this in setUpAll() for tests that need Magic services like Log, Http.
Future<void> initMagicForTests() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: []);
}
