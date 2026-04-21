import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../config.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _canSubmit = false;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_syncCanSubmit);
    _passwordController.addListener(_syncCanSubmit);
    _syncCanSubmit();
  }

  void _syncCanSubmit() {
    final next = _usernameController.text.trim().isNotEmpty && _passwordController.text.isNotEmpty;
    if (next == _canSubmit) return;
    setState(() => _canSubmit = next);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final authNotifier = ref.read(authProvider.notifier);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF667eea), Color(0xFF764ba2)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            Icons.school,
                            size: 40,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Attendify',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sign in to continue',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Colors.black54,
                              ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _usernameController,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock),
                          ),
                          onSubmitted: authState.isLoading
                              ? null
                              : (_) async {
                                  if (!_canSubmit) return;
                                  final msg = await authNotifier.login(
                                    _usernameController.text,
                                    _passwordController.text,
                                  );
                                  if (!context.mounted) return;
                                  if (msg != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  }
                                },
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: (authState.isLoading || !_canSubmit)
                              ? null
                              : () async {
                                  final msg = await authNotifier.login(
                                    _usernameController.text,
                                    _passwordController.text,
                                  );
                                  if (!context.mounted) return;
                                  if (msg != null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)),
                                    );
                                  }
                                },
                          child: authState.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Login'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('No account?'),
                            TextButton(
                              onPressed: () => _showRegisterDialog(context, authNotifier),
                              child: const Text('Create Account'),
                            ),
                          ],
                        ),
                        if (!lockServerSettings) ...[
                          const SizedBox(height: 4),
                          OutlinedButton.icon(
                            onPressed: () => _showServerDialog(context),
                            icon: const Icon(Icons.settings),
                            label: const Text('Server Settings'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRegisterDialog(BuildContext context, AuthNotifier notifier) {
    String role = 'student';
    final usernameController = TextEditingController(text: _usernameController.text);
    final passwordController = TextEditingController(text: _passwordController.text);
    final fullNameController = TextEditingController();
    final studentIdController = TextEditingController();
    const courses = [
      'Bachelor of Science in Criminology',
      'Bachelor of Science in Information System',
      'Bachelor of Science in Psychology',
      'Bachelor of Science in Accounting Information System',
      'Bachelor of Secondary Education',
      'Bachelor of Science in Accountancy',
    ];
    const courseCodes = {
      'Bachelor of Science in Criminology': 'BSC',
      'Bachelor of Science in Information System': 'BSIS',
      'Bachelor of Science in Psychology': 'BSP',
      'Bachelor of Science in Accounting Information System': 'BSAIS',
      'Bachelor of Secondary Education': 'BSED',
      'Bachelor of Science in Accountancy': 'BSA',
    };
    String? selectedCourse;
    int? selectedYear;
    String? selectedSection;

    List<String> buildSections() {
      if (selectedCourse == null || selectedYear == null) return const [];
      final code = courseCodes[selectedCourse] ?? 'BS';
      return List<String>.generate(
        26,
        (i) => '$code $selectedYear${String.fromCharCode(65 + i)}',
      );
    }
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Register'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password'),
              ),
              TextField(
                controller: fullNameController,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              if (role == 'student')
                TextField(
                  controller: studentIdController,
                  decoration: const InputDecoration(labelText: 'Student ID'),
                ),
              if (role == 'student')
                DropdownButtonFormField<String>(
                  initialValue: selectedCourse,
                  decoration: const InputDecoration(labelText: 'Course'),
                  hint: const Text('Select course'),
                  items: courses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setState(() {
                    selectedCourse = v;
                    selectedSection = null;
                  }),
                ),
              if (role == 'student')
                DropdownButtonFormField<int>(
                  initialValue: selectedYear,
                  decoration: const InputDecoration(labelText: 'Year Level'),
                  hint: const Text('Select year'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1st Year')),
                    DropdownMenuItem(value: 2, child: Text('2nd Year')),
                    DropdownMenuItem(value: 3, child: Text('3rd Year')),
                    DropdownMenuItem(value: 4, child: Text('4th Year')),
                  ],
                  onChanged: (v) => setState(() {
                    selectedYear = v;
                    selectedSection = null;
                  }),
                ),
              if (role == 'student')
                DropdownButtonFormField<String>(
                  initialValue: selectedSection,
                  decoration: const InputDecoration(labelText: 'Section'),
                  hint: const Text('Select section'),
                  items: buildSections().map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setState(() => selectedSection = v),
                ),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  DropdownMenuItem(value: 'faculty', child: Text('Faculty')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    role = value;
                    if (role != 'student') {
                      selectedCourse = null;
                      selectedYear = null;
                      selectedSection = null;
                    }
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final username = usernameController.text.trim();
                final password = passwordController.text;
                final fullName = fullNameController.text.trim();
                final studentId = studentIdController.text.trim();
                if (username.isEmpty || password.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter username and password')),
                    );
                  }
                  return;
                }
                if (role == 'student' &&
                    (fullName.isEmpty || studentId.isEmpty || selectedCourse == null || selectedYear == null || selectedSection == null)) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter full name, student ID, course, year, and section')),
                    );
                  }
                  return;
                }
                final msg = await notifier.register(
                  username,
                  password,
                  role,
                  fullName: fullName.isEmpty ? null : fullName,
                  studentId: role == 'student' ? studentId : null,
                  course: role == 'student' ? selectedCourse : null,
                  section: role == 'student' ? selectedSection : null,
                );
                if (context.mounted && msg != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg)),
                  );
                  return;
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showServerDialog(BuildContext context) async {
    final base = await ApiClient.getBaseUrl();
    if (!context.mounted) return;
    final controller = TextEditingController(text: base);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Base URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'http://<your-ip>:3000/api',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              await ApiClient.setBaseUrl(controller.text.trim());
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
