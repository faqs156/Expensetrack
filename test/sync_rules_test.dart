import 'package:expense_track/core/sync_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyncRules.decide', () {
    test('both devices keep each others transactions', () {
      final d = SyncRules.decide(
        localTxIds: {'a'},
        remoteTxIds: {'b'},
        mergedTxIds: {'a', 'b'},
        hasPendingLocalEdits: true,
      );
      expect(d.restoreLocal, isTrue);
      expect(d.uploadRemote, isTrue);
      expect(d.refuseUpload, isFalse);
    });

    test('refuses upload that would drop remote ids', () {
      final d = SyncRules.decide(
        localTxIds: {'a'},
        remoteTxIds: {'a', 'b'},
        mergedTxIds: {'a'},
        hasPendingLocalEdits: true,
      );
      expect(d.refuseUpload, isTrue);
      expect(d.uploadRemote, isFalse);
    });

    test('no-op when already in sync', () {
      final d = SyncRules.decide(
        localTxIds: {'a', 'b'},
        remoteTxIds: {'a', 'b'},
        mergedTxIds: {'a', 'b'},
        hasPendingLocalEdits: false,
      );
      expect(d.restoreLocal, isFalse);
      expect(d.uploadRemote, isFalse);
    });

    test('empty remote with local data uploads', () {
      final d = SyncRules.decide(
        localTxIds: {'a'},
        remoteTxIds: {},
        mergedTxIds: {'a'},
        hasPendingLocalEdits: false,
      );
      expect(d.uploadRemote, isTrue);
      expect(d.restoreLocal, isFalse);
    });
  });
}
