import 'package:greenflags/greenflags.dart';

Future<void> main() async {
  final flags = GreenFlagsClient(
    url: 'https://app.greenflags.dev',
    apiToken: const String.fromEnvironment(
      'GREENFLAGS_TOKEN',
      defaultValue: 'gf_your_token_here',
    ),
  );

  await flags.refresh();

  for (final flag in flags.getAllFlags()) {
    print('${flag.key} (${flag.type.wire}) = ${flag.value}');
  }

  if (flags.isEnabled('new-checkout')) {
    print('new checkout is ON');
  }

  flags.dispose();
}
