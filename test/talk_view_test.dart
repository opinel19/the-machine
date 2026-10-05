import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:person_of_interest/src/machine/machine_controller.dart';
import 'package:person_of_interest/src/storage/identity_store.dart';
import 'package:person_of_interest/src/storage/settings.dart';
import 'package:person_of_interest/src/ui/talk_view.dart';

void main() {
  const channel = MethodChannel('poi/native');
  late List<MethodCall> calls;
  late MachineController controller;

  /// The platform side reporting speech, as MachineListener does.
  Future<void> native(String type, {String text = ''}) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'poi/native',
      channel.codec.encodeMethodCall(MethodCall('onSpeech', {'type': type, 'text': text, 'level': 0.5})),
      (_) {},
    );
  }

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'listen' ? true : null;
    });
    controller = MachineController(identities: IdentityStore(), settings: MachineSettings());
  });

  tearDown(() => controller.dispose());

  Future<void> openTalk(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(onPressed: () => showTalk(context, controller), child: const Text('TALK')),
        ),
      ),
    );
    await tester.tap(find.text('TALK'));
    await tester.pump(const Duration(milliseconds: 300));
  }

  int listens() => calls.where((c) => c.method == 'listen').length;

  testWidgets('a spoken question is answered out loud, then it listens again until silence', (tester) async {
    await openTalk(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump(const Duration(milliseconds: 100));
    expect(listens(), 1);
    expect(calls.lastWhere((c) => c.method == 'listen').arguments, controller.settings.talkLocale);

    await native('partial', text: 'who are');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('WHO ARE'), findsOneWidget);

    await native('final', text: 'who are you');
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('> WHO ARE YOU'), findsOneWidget);
    final spoken = calls.lastWhere((c) => c.method == 'speak').arguments as Map;
    expect((spoken['words'] as List).join(' '), contains('MACHINE'));

    // Not while it is still talking; once it is done, it listens again.
    await tester.pump(const Duration(seconds: 2));
    expect(listens(), 1);
    await native('spoken');
    await tester.pump(const Duration(milliseconds: 400));
    expect(listens(), 2);

    // Nobody says anything: the conversation is over.
    await native('final');
    await native('spoken');
    await tester.pump(const Duration(seconds: 2));
    expect(listens(), 2);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('the microphone refused says so', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'listen') throw PlatformException(code: 'denied');
      return null;
    });
    await openTalk(tester);
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('ACCESS DENIED'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });
}
