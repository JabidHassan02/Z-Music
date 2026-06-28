import 'package:flutter_test/flutter_test.dart';

// Make sure this matches the name in your pubspec.yaml
import 'package:music_app/main.dart'; 

void main() {
  testWidgets('Music App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const ModernMusicApp());

    // Verify that our app successfully loads the main screen
    // by checking if the 'Library' header is present.
    expect(find.text('Library'), findsOneWidget);
  });
}