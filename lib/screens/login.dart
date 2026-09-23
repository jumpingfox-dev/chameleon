import 'package:material_ui/material_ui.dart';
import 'package:forui/forui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  @override
  Widget build(BuildContext context) {
    return const FScaffold(
      header: FHeader(
        title: Text('Sign In'),
      ),
      child: Center(
        child: Text('Login Screen'),
      ),
    );
  }
}
