import 'package:flutter_test/flutter_test.dart';

import 'package:travel_route_planner/main.dart';

/// A deep link must boot on exactly one route. The framework default expands
/// `/share/x` into a stack of every path prefix; the prefixes hit the
/// AuthGate catch-all and a signed-in session then mounts two AppShells whose
/// tab navigators collide on the same GlobalKeys (blank-screen tree
/// corruption). Regression test for generateInitialRoutes.
void main() {
  test('deep links generate a single initial route', () {
    for (final path in [
      '/',
      '/share/tok123',
      '/invite/tok123',
      '/reset/tok123',
      '/verify/tok123',
      '/sso/code123',
      '/alerts',
    ]) {
      final routes = generateInitialRoutes(path);
      expect(routes, hasLength(1), reason: 'path $path');
      expect(routes.single.settings.name, path);
    }
  });
}
