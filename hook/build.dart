import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: 'flare_bindings_generated.dart',
      sources: ['src/flare.cpp'],
      libraries: [if (input.config.code.targetOS == OS.windows) 'bcrypt'],
      flags: [
        if (input.config.buildCodeAssets &&
            input.config.code.targetOS == OS.android)
          '-Wl,-z,max-page-size=16384',
      ],
    );
    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => stdout.writeln(record.message)),
    );
  });
}
