import 'package:flutter/widgets.dart';
import 'package:voice_social_app/app/app.dart';
import 'package:voice_social_app/app/app_dependencies.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final AppDependencies dependencies = AppDependencies.fromEnvironment();
    dependencies.environment.validateLiveConfiguration();
    runApp(VoiceSocialApp(dependencies: dependencies));
  } catch (error) {
    runApp(BootstrapFailureApp(message: error.toString()));
  }
}
