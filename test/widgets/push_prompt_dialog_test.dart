import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

void main() {
  testWidgets('PushPromptDialog shows title and message', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PushPromptDialog(
            title: 'Stay Updated',
            message: 'Get notified when monitors go down.',
            acceptText: 'Enable',
            declineText: 'Not Now',
            onAccept: () {},
            onDecline: () {},
          ),
        ),
      ),
    );

    expect(find.text('Stay Updated'), findsOneWidget);
    expect(find.text('Get notified when monitors go down.'), findsOneWidget);
    expect(find.text('Enable'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);
  });

  testWidgets('Accept button calls onAccept', (tester) async {
    var accepted = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PushPromptDialog(
            onAccept: () => accepted = true,
            onDecline: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Enable'));
    expect(accepted, isTrue);
  });

  testWidgets('Decline button calls onDecline', (tester) async {
    var declined = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PushPromptDialog(
            onAccept: () {},
            onDecline: () => declined = true,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Not Now'));
    expect(declined, isTrue);
  });
}
