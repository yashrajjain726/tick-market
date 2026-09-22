import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'feature dependencies point inward and core stays feature independent',
    () {
      final library = Directory('lib').absolute.uri;
      final directives = RegExp(
        r'''\b(?:import|export|part)\s+['"]([^'"]+)['"]''',
      );
      final violations = <String>[];
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        final path = file.absolute.uri.path.substring(library.path.length);
        for (final directive in directives.allMatches(
          file.readAsStringSync(),
        )) {
          final target = directive.group(1)!;
          final uri = target.startsWith('package:tick_market/')
              ? library.resolve(target.substring('package:tick_market/'.length))
              : file.absolute.uri.resolve(target);
          final local =
              uri.scheme == 'file' && uri.path.startsWith(library.path)
              ? uri.path.substring(library.path.length)
              : null;
          final domain = path.startsWith('features/market/domain/');
          final data = path.startsWith('features/market/data/');
          final presentation = path.startsWith('features/market/presentation/');
          final core = path.startsWith('core/');
          final forbidden =
              (domain &&
                  !(target.startsWith('dart:') &&
                      ![
                        'dart:io',
                        'dart:convert',
                        'dart:ui',
                      ].contains(target)) &&
                  !(local?.startsWith('features/market/domain/') ?? false)) ||
              (data &&
                  ((local?.startsWith('app/') ?? false) ||
                      (local?.contains('/presentation/') ?? false))) ||
              (presentation &&
                  ((local?.startsWith('app/') ?? false) ||
                      (local?.contains('/data/') ?? false) ||
                      (local?.startsWith('core/network/') ?? false) ||
                      target == 'dart:io')) ||
              (core &&
                  ((local?.startsWith('features/') ?? false) ||
                      (local?.startsWith('app/') ?? false)));
          if (forbidden) violations.add('$path → $target');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Only the composition root wires layers.',
      );
    },
  );
}
