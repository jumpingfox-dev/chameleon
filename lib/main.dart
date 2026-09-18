import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:google_fonts/google_fonts.dart';

String primaryFont = 'Outfit';
String secondaryFont = 'Instrument Sans';
String tertiaryFont = 'JetBrains Mono';
String loremIpsum = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(MaterialApp(
    home: Home(),
  ));
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Text(
          selectionColor: Colors.black,
          'Welcome',
          style:
          GoogleFonts.getFont(
            primaryFont,
            fontSize: 30.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: Colors.grey[600],
          ),
        ),
      ),
      body: Center(
        child: Text(
          loremIpsum,
          style: GoogleFonts.getFont(
            secondaryFont,
            fontSize: 30.0,
            fontWeight: FontWeight.bold,
            letterSpacing: 2.0,
            color: Colors.black,
          ),
          selectionColor: Colors.white,
        ),

      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: Text(
          'Click',
          style: GoogleFonts.getFont(
            tertiaryFont,
          )
        ),
      ),
    );
  }
}
