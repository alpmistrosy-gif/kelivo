import 'package:Kelivo/features/home/services/normal_turn_tool_history_compactor.dart';

void expect(bool value, String label) {
  if (!value) throw StateError('FAILED: $label');
}

Map<String, dynamic> user(String text) => {'role': 'user', 'content': text};
Map<String, dynamic> story(String text) => {'role': 'assistant', 'content': text};
Map<String, dynamic> call(String id, String name) => {
  'role': 'assistant', 'content': null,
  'tool_calls': [{'id': id, 'type': 'function', 'function': {'name': name, 'arguments': '{}'}}],
};
Map<String, dynamic> result(String id, String text) =>
    {'role': 'tool', 'tool_call_id': id, 'content': text};

void main() {
  const compact = NormalTurnToolHistoryCompactor();
  const on = NormalTurnHistoryCompactionPolicy(enabled: true, fixtureMode: true);
  const off = NormalTurnHistoryCompactionPolicy();
  final safe = [user('u'), story('story'), call('x', 'read_test_brief'), result('x', 'fixture'), user('last user')];
  final reduced = compact.buildRequestMessages(safe, on);
  expect(reduced.length == 3, 'complete fixture pair removed');
  expect(reduced.last['content'] == 'last user', 'last user preserved');
  expect(safe.length == 5, 'source view not mutated');
  expect(compact.requestJsonUtf8Bytes(reduced) < compact.requestJsonUtf8Bytes(safe), 'bytes reduced');
  expect(compact.buildRequestMessages(safe, off).length == safe.length, 'default off');
  expect(compact.buildRequestMessages(safe, const NormalTurnHistoryCompactionPolicy(enabled: true, fixtureMode: true, currentToolContinuation: true)).length == safe.length, 'continuation untouched');
  expect(compact.buildRequestMessages([call('x', 'game_recall'), result('x', 'r')], on).length == 2, 'production read retained');
  expect(compact.buildRequestMessages([call('x', 'save_game'), result('x', 'r')], on).length == 2, 'production write retained');
  expect(compact.buildRequestMessages([call('x', 'read_test_brief')], on).length == 1, 'unfinished retained');
  expect(compact.buildRequestMessages([{'role': 'assistant', 'content': 'narrative', 'tool_calls': call('x', 'read_test_brief')['tool_calls']}, result('x', 'r')], on).length == 2, 'narrative retained');
  expect(compact.buildRequestMessages([{...call('x', 'read_test_brief'), 'reasoning_content': 'r'}, result('x', 'r')], on).length == 2, 'reasoning retained');
  expect(compact.buildRequestMessages([call('x', 'read_test_brief'), result('x', 'one'), result('x', 'two')], on).length == 3, 'duplicate result retained');

  // Regression: never leave orphan tool messages.
  expect(compact.buildRequestMessages([
    call('x', 'read_test_brief'), result('other', 'bad'), result('x','ok'),
  ], on).length == 3, 'foreign tool result preserved');
  expect(compact.buildRequestMessages([
    call('x', 'read_test_brief'), result('x','ok'), result('other', 'bad'),
  ], on).length == 3, 'extra tool result preserved');
  expect(compact.buildRequestMessages([
    call('x', 'read_test_brief'), {'role':'tool','tool_call_id':'x','content':null},
  ], on).length == 2, 'null tool result preserved');
  expect(compact.buildRequestMessages([
    {...call('x','read_test_brief'), 'reasoning_details': [{'reasoning':'signed'}]},
    result('x','ok'),
  ], on).length == 2, 'signed reasoning preserved');
  final mixedCalls = [
    {'id':'x','type':'function','function':{'name':'read_test_brief','arguments':'{}'}},
    {'id':'y','type':'function','function':{'name':'save_game','arguments':'{}'}},
  ];
  expect(compact.buildRequestMessages([
    {'role':'assistant','content':null,'tool_calls': mixedCalls},
    result('x','ok'),result('y','saved'),
  ], on).length == 3, 'mixed read and write retained');
  final sixStory = [for (var i=1; i<=6; i++) ...[user('turn $i'),story('story $i')]];
  expect(compact.buildRequestMessages(sixStory, on).length == sixStory.length, 'six normal turns unchanged');
  print('PASS: test-only compactor safety cases');

}
