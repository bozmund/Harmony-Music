import 'package:flutter_test/flutter_test.dart';
import 'package:harmonymusic/utils/helper.dart';

void main() {
  group('stable update semantic version comparison', () {
    test('does not offer v6.0.2 to an internally versioned 6.0.2 build', () {
      expect(isSemanticVersionNewer('v6.0.2', 'V6.0.2'), isFalse);
    });

    test('offers a newer stable tag', () {
      expect(isSemanticVersionNewer('v6.0.3', 'V6.0.2'), isTrue);
    });

    test('ignores build metadata when comparing stable versions', () {
      expect(isSemanticVersionNewer('v6.0.2', '6.0.2+30'), isFalse);
    });
  });
}
