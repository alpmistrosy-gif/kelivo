// Test-only request-view experiment. It must never rewrite persisted history.
import 'dart:convert';

/// This is deliberately a compile-time, opt-in test flag. Production builds
/// cannot enable the experiment through settings, remote configuration, or MCP.
const bool kEnableReadTestBriefHistoryCompaction = bool.fromEnvironment(
  'KELIVO_TEST_ONLY_READ_TEST_BRIEF_HISTORY_COMPACTION',
  defaultValue: false,
);

final class NormalTurnHistoryCompactionPolicy {
  const NormalTurnHistoryCompactionPolicy({
    this.enabled = false,
    this.fixtureMode = false,
    this.currentToolContinuation = false,
    this.allowedToolNames = const {'read_test_brief'},
  });

  final bool enabled;
  final bool fixtureMode;
  final bool currentToolContinuation;
  final Set<String> allowedToolNames;

  bool get mayCompact => enabled && fixtureMode && !currentToolContinuation;
}

/// Copies a provider request view and removes only complete, contentless,
/// whitelisted assistant-tool/result units. Any unknown shape is retained.
final class NormalTurnToolHistoryCompactor {
  const NormalTurnToolHistoryCompactor();

  List<Map<String, dynamic>> buildRequestMessages(
    List<Map<String, dynamic>> persistedMessages,
    NormalTurnHistoryCompactionPolicy policy,
  ) {
    final copied = persistedMessages.map(_copy).toList(growable: false);
    if (!policy.mayCompact) return copied;

    final drop = <int>{};
    for (var index = 0; index < copied.length; index++) {
      final assistant = copied[index];
      if (assistant['role'] != 'assistant' || !_hasNoNarrative(assistant)) continue;
      final calls = assistant['tool_calls'];
      if (calls is! List || calls.isEmpty) continue;
      final callIds = <String>{};
      var eligible = true;
      for (final rawCall in calls) {
        if (rawCall is! Map || rawCall.keys.any((key) => key is! String)) {
          eligible = false;
          break;
        }
        final call = Map<String, dynamic>.from(rawCall);
        final id = call['id'];
        final function = call['function'];
        final name = function is Map ? function['name'] : null;
        if (id is! String || id.isEmpty || name is! String ||
            name != 'read_test_brief' || !policy.allowedToolNames.contains(name)) {
          eligible = false;
          break;
        }
        callIds.add(id);
      }
      if (!eligible || callIds.length != calls.length) continue;

      final resultIndexes = <int>[];
      for (var next = index + 1; next < copied.length; next++) {
        final candidate = copied[next];
        if (candidate['role'] != 'tool') break;
        final id = candidate['tool_call_id'];
        if (id is! String || !callIds.contains(id) || candidate['content'] == null) {
          eligible = false;
          break;
        }
        resultIndexes.add(next);
      }
      final resultIds = {
        for (final i in resultIndexes) copied[i]['tool_call_id'] as String,
      };
      if (!eligible || resultIndexes.length != callIds.length ||
          resultIds.length != callIds.length || !resultIds.containsAll(callIds)) {
        continue;
      }
      drop.add(index);
      drop.addAll(resultIndexes);
    }
    return [for (var i = 0; i < copied.length; i++) if (!drop.contains(i)) copied[i]];
  }

  int requestJsonUtf8Bytes(List<Map<String, dynamic>> messages) =>
      utf8.encode(jsonEncode({'messages': messages})).length;

  Map<String, dynamic> _copy(Map<String, dynamic> message) =>
      Map<String, dynamic>.from(message);

  bool _hasNoNarrative(Map<String, dynamic> message) {
    final content = message['content'];
    if (content != null && content != '') return false;
    for (final field in ['reasoning', 'reasoning_content', 'reasoning_details']) {
      final value = message[field];
      if (value != null && value != '' && value != false &&
          !(value is List && value.isEmpty) && !(value is Map && value.isEmpty)) {
        return false;
      }
    }
    return true;
  }
}
