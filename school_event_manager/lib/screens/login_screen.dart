import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show MyApp;
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart' show AuthService;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _canSubmit = false;
  bool _obscurePassword = true;

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

  bool _isStrongPassword(String password) {
    // At least 8 characters long
    // Contains at least one uppercase letter
    // Contains at least one lowercase letter
    // Contains at least one digit
    // Contains at least one special character
    final strongPasswordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#$%^&*])(?=.{8,})');
    return strongPasswordRegex.hasMatch(password);
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
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock),
                            suffixIcon: IconButton(
                              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            ),
                          ),
                          onSubmitted: authState.isLoading
                              ? null
                              : (_) async {
                                  if (!_canSubmit) return;
                                  final ctx = context;
                                  final messenger = MyApp.scaffoldMessengerKey.currentState ??
                                      ScaffoldMessenger.of(ctx);
                                  Future<AuthActionResult> doLogin() => authNotifier.login(
                                        _usernameController.text,
                                        _passwordController.text,
                                      );
                                  AuthActionResult result = await doLogin();
                                  if (!ctx.mounted) return;
                                  if (result.succeeded) return;
                                  if (result.isEmailVerificationRequired) {
                                    // Try OTP verification. If user successfully verifies,
                                    // AUTO-RE-ATTEMPT login immediately so they don't have to
                                    // click Login again.
                                    final closed = await _showOtpDialog(
                                      ctx,
                                      username: result.username ?? _usernameController.text.trim(),
                                      email: result.email,
                                      expiresInMs: result.expiresInMs,
                                      emailSent: result.emailSent ?? false,
                                    );
                                    if (!ctx.mounted) return;
                                    if (closed == true) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Email verified! Signing you in…',
                                          ),
                                        ),
                                      );
                                      final retry = await doLogin();
                                      if (!ctx.mounted) return;
                                      if (retry.succeeded) return;
                                      if (retry.errorMessage != null) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text(retry.errorMessage!)),
                                        );
                                      }
                                    }
                                    return;
                                  }
                                  final err = result.errorMessage;
                                  if (err != null) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(err)),
                                    );
                                  }
                                },
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: (authState.isLoading || !_canSubmit)
                              ? null
                              : () async {
                                  final ctx = context;
                                  final messenger = MyApp.scaffoldMessengerKey.currentState ??
                                      ScaffoldMessenger.of(ctx);
                                  Future<AuthActionResult> doLogin() => authNotifier.login(
                                        _usernameController.text,
                                        _passwordController.text,
                                      );
                                  AuthActionResult result = await doLogin();
                                  if (!ctx.mounted) return;
                                  if (result.succeeded) return;
                                  if (result.isEmailVerificationRequired) {
                                    final closed = await _showOtpDialog(
                                      ctx,
                                      username: result.username ?? _usernameController.text.trim(),
                                      email: result.email,
                                      expiresInMs: result.expiresInMs,
                                      emailSent: result.emailSent ?? false,
                                    );
                                    if (!ctx.mounted) return;
                                    if (closed == true) {
                                      messenger.showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Email verified! Signing you in…',
                                          ),
                                        ),
                                      );
                                      final retry = await doLogin();
                                      if (!ctx.mounted) return;
                                      if (retry.succeeded) return;
                                      if (retry.errorMessage != null) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text(retry.errorMessage!)),
                                        );
                                      }
                                    }
                                    return;
                                  }
                                  final err = result.errorMessage;
                                  if (err != null) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text(err)),
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
                        TextButton(
                          onPressed: authState.isLoading ? null : () => _showResetPasswordDialog(context),
                          child: const Text('Reset Password'),
                        ),
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
    bool obscureRegisterPassword = true;
    final usernameController = TextEditingController(text: _usernameController.text);
    final passwordController = TextEditingController(text: _passwordController.text);
    final fullNameController = TextEditingController();
    final studentIdController = TextEditingController();
    final emailController = TextEditingController(text: _usernameController.text.trim());
    final otpController = TextEditingController();
    const courses = [
      'Bachelor of Science in Criminology',
      'Bachelor of Science in Information System',
      'Bachelor of Science in Psychology',
      'Bachelor of Science in Accounting Information System',
      'Bachelor of Secondary Education',
      'Bachelor of Science in Accountancy',
    ];
    const Map<String, String> courseCodes = {
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
    // ---- Pre-registration OTP state (Student only) ----
    int studentStage = 1; // 1 = send-otp screen; 2 = otp + details screen
    bool sendingOtp = false;
    int sendCooldownSec = 0;
    Timer? sendCooldownTimer;
    String? pendingOtpRef;
    String? pendingOtpEmail;
    int? pendingOtpExpiresInMs;
    bool lastEmailSent = false;
    String? emailInlineError;
    String? otpInlineError;

    List<String> buildSections() {
      if (selectedCourse == null || selectedYear == null) return const [];
      final code = courseCodes[selectedCourse!] ?? 'BS';
      return List<String>.generate(
        26,
        (i) => '$code $selectedYear${String.fromCharCode(65 + i)}',
      );
    }

    String expiryLabel(int? ms) {
      if (ms == null) return 'for 10 minutes';
      final total = (ms / 1000).round();
      final mins = total ~/ 60;
      final secs = total % 60;
      if (mins <= 0) return 'for $secs seconds';
      if (secs == 0) return 'for $mins minutes';
      return 'for $mins min $secs s';
    }

    showDialog<void>(
      context: context,
      builder: (context) {
        final rootMessenger = MyApp.scaffoldMessengerKey.currentState;
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            void refresh(void Function() fn) {
              if (ModalRoute.of(context)?.isActive ?? false) setStateDialog(fn);
            }

            void startSendCooldown(int secs) {
              sendCooldownSec = secs;
              sendCooldownTimer?.cancel();
              sendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                final next = sendCooldownSec - 1;
                if (next <= 0) {
                  sendCooldownSec = 0;
                  t.cancel();
                } else {
                  sendCooldownSec = next;
                }
                if (ModalRoute.of(context)?.isActive ?? false) {
                  setStateDialog(() {});
                } else {
                  t.cancel();
                }
              });
            }

            Future<void> doSendOtp() async {
              final routeActive = ModalRoute.of(context);
              final email = emailController.text.trim();
              final emailOk = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email);
              if (!emailOk) {
                refresh(() => emailInlineError = 'Enter a valid Gmail address (e.g. name@gmail.com).');
                return;
              }
              refresh(() {
                sendingOtp = true;
                emailInlineError = null;
              });
              final res = await notifier.sendRegistrationOtp(email);
              if (!(routeActive?.isActive ?? false)) return;
              if (res.ok) {
                startSendCooldown(60);
                pendingOtpRef = res.ref;
                pendingOtpEmail = res.email ?? email.toLowerCase();
                pendingOtpExpiresInMs = res.expiresInMs ?? 10 * 60 * 1000;
                lastEmailSent = res.emailSent;
                rootMessenger?.showSnackBar(
                  SnackBar(
                    content: Text(
                      res.message ??
                          (res.emailSent
                              ? 'Verification code emailed. Check your Gmail inbox (and Spam folder).'
                              : 'Verification code generated. Check server logs for "[mail][code]" or your Gmail inbox.'),
                    ),
                  ),
                );
                refresh(() {
                  sendingOtp = false;
                  studentStage = 2;
                  otpController.clear();
                  otpInlineError = null;
                });
              } else {
                refresh(() {
                  sendingOtp = false;
                  emailInlineError = res.message ?? 'Could not send verification code. Try again.';
                });
              }
            }

            return PopScope(
              canPop: true,
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) sendCooldownTimer?.cancel();
              },
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Register'),
                    if (role == 'student')
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          studentStage == 1
                              ? 'Step 1 of 2: Verify your email first'
                              : 'Step 2 of 2: Enter code + account details',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                  ],
                ),
                content: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 430,
                    maxHeight: MediaQuery.of(context).size.height * 0.72,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // -------- Role selector (always visible so user can switch) --------
                        DropdownButtonFormField<String>(
                          initialValue: role,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: const [
                            DropdownMenuItem(value: 'student', child: Text('Student')),
                            DropdownMenuItem(value: 'faculty', child: Text('Faculty')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setStateDialog(() {
                              role = value;
                              selectedCourse = null;
                              selectedYear = null;
                              selectedSection = null;
                              if (role == 'student') {
                                studentStage = 1;
                                pendingOtpRef = null;
                                pendingOtpEmail = null;
                                otpController.clear();
                                otpInlineError = null;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        if (role == 'student') ...[
                          // ---- Stage 1: Email + Send code button ----
                          if (studentStage == 1) ...[
                            TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) {
                                if (!sendingOtp && sendCooldownSec == 0) doSendOtp();
                              },
                              decoration: InputDecoration(
                                labelText: 'Gmail address',
                                prefixIcon: const Icon(Icons.email_outlined),
                                errorText: emailInlineError,
                                helperText: 'After clicking Send, check your Gmail for a 6-digit code.',
                                helperMaxLines: 3,
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: (sendingOtp || sendCooldownSec > 0)
                                    ? null
                                    : doSendOtp,
                                icon: sendingOtp
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.send_to_mobile_outlined),
                                label: Text(
                                  sendingOtp
                                      ? 'Sending code…'
                                      : sendCooldownSec > 0
                                          ? 'Resend code ($sendCooldownSec s)'
                                          : 'Send verification code',
                                ),
                              ),
                            ),
                          ],
                          // ---- Stage 2: OTP + remaining form ----
                          if (studentStage == 2) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: lastEmailSent
                                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
                                    : Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: lastEmailSent
                                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.25)
                                      : Colors.amber.shade200,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    lastEmailSent ? Icons.mark_email_read_outlined : Icons.info_outline,
                                    size: 18,
                                    color: lastEmailSent
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.amber,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      lastEmailSent
                                          ? 'Code sent to ${pendingOtpEmail ?? emailController.text.trim()}. Valid ${expiryLabel(pendingOtpExpiresInMs)}.'
                                          : 'Code generated for ${pendingOtpEmail ?? emailController.text.trim()}. Check server logs: "[mail][code]". Valid ${expiryLabel(pendingOtpExpiresInMs)}.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: lastEmailSent
                                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                                : Colors.amber.shade900,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: otpController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                    letterSpacing: 8,
                                    fontWeight: FontWeight.w700,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: InputDecoration(
                                labelText: '6-digit verification code',
                                hintText: '000000',
                                errorText: otpInlineError,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                counterText: '${otpController.text.length}/6',
                              ),
                              onChanged: (_) => setStateDialog(() {}),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: (sendingOtp || sendCooldownSec > 0)
                                    ? null
                                    : doSendOtp,
                                icon: sendingOtp
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh, size: 16),
                                label: Text(
                                  sendCooldownSec > 0
                                      ? 'Resend code ($sendCooldownSec s)'
                                      : 'Resend verification code',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: passwordController,
                              obscureText: obscureRegisterPassword,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                suffixIcon: IconButton(
                                  tooltip: obscureRegisterPassword ? 'Show password' : 'Hide password',
                                  onPressed: () => setStateDialog(
                                      () => obscureRegisterPassword = !obscureRegisterPassword),
                                  icon: Icon(obscureRegisterPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: fullNameController,
                              decoration: const InputDecoration(labelText: 'Full name'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: studentIdController,
                              decoration: const InputDecoration(labelText: 'Student ID'),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: selectedCourse,
                              isExpanded: true,
                              menuMaxHeight: 320,
                              decoration: const InputDecoration(labelText: 'Course'),
                              hint: const Text('Select course'),
                              items: courses
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              selectedItemBuilder: (context) => courses
                                  .map(
                                    (c) => Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        c,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setStateDialog(() {
                                selectedCourse = v;
                                selectedSection = null;
                              }),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              initialValue: selectedYear,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Year Level'),
                              hint: const Text('Select year'),
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('1st Year')),
                                DropdownMenuItem(value: 2, child: Text('2nd Year')),
                                DropdownMenuItem(value: 3, child: Text('3rd Year')),
                                DropdownMenuItem(value: 4, child: Text('4th Year')),
                              ],
                              onChanged: (v) => setStateDialog(() {
                                selectedYear = v;
                                selectedSection = null;
                              }),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              initialValue: selectedSection,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Section'),
                              hint: const Text('Select section'),
                              items: buildSections()
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setStateDialog(() => selectedSection = v),
                            ),
                          ],
                        ] else ...[
                          // -------------- FACULTY flow (unchanged) --------------
                          TextField(
                            controller: usernameController,
                            decoration: const InputDecoration(labelText: 'Username'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: passwordController,
                            obscureText: obscureRegisterPassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                tooltip: obscureRegisterPassword ? 'Show password' : 'Hide password',
                                onPressed: () => setStateDialog(
                                    () => obscureRegisterPassword = !obscureRegisterPassword),
                                icon: Icon(obscureRegisterPassword
                                    ? Icons.visibility_off
                                    : Icons.visibility),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: fullNameController,
                            decoration: const InputDecoration(labelText: 'Full name'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actions: [
                  if (role == 'student' && studentStage == 2)
                    TextButton(
                      onPressed: () => setStateDialog(() {
                        studentStage = 1;
                        otpInlineError = null;
                      }),
                      child: const Text('Change email'),
                    ),
                  TextButton(
                    onPressed: () {
                      sendCooldownTimer?.cancel();
                      Navigator.pop(context);
                    },
                    child: const Text('Cancel'),
                  ),
                  // ---- Primary action button ----
                  if (role == 'student' && studentStage == 1)
                    ElevatedButton(
                      onPressed: (sendingOtp || sendCooldownSec > 0) ? null : doSendOtp,
                      child: Text(sendingOtp ? 'Sending…' : 'Send code & continue'),
                    )
                  else
                    ElevatedButton(
                      onPressed: () async {
                        final ctx = context;
                        final messenger = MyApp.scaffoldMessengerKey.currentState ??
                            ScaffoldMessenger.of(ctx);
                        final navigator = Navigator.of(ctx);
                        final password = passwordController.text;
                        final fullName = fullNameController.text.trim();
                        final studentId = studentIdController.text.trim();
                        final email = role == 'student'
                            ? ((pendingOtpEmail?.isNotEmpty == true
                                        ? pendingOtpEmail
                                        : emailController.text.trim()) ??
                                    emailController.text.trim())
                                .toLowerCase()
                            : emailController.text.trim();
                        String username = usernameController.text.trim();
                        String? otp;
                        String? otpRef;
                        if (role == 'student') {
                          username = email;
                          otp = otpController.text.trim();
                          otpRef = pendingOtpRef;
                        }
                        if (username.isEmpty || password.isEmpty) {
                          // For student: if email controller was ever empty, Stage1 would never send;
                          // defensively fall back to asking user via inline or snack.
                          if (role == 'student' && username.isEmpty) {
                            setStateDialog(() {
                              studentStage = 1;
                              emailInlineError =
                                  'Enter your Gmail first, then tap "Send verification code".';
                            });
                          } else {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  role == 'student'
                                      ? 'Enter email and password'
                                      : 'Enter username and password',
                                ),
                              ),
                            );
                          }
                          return;
                        }
                        if (role == 'student') {
                          if (otp == null || otp.length != 6) {
                            setStateDialog(() {
                              otpInlineError = 'Enter the 6-digit code we sent to your Gmail.';
                            });
                            return;
                          }
                          if (otpRef == null || otpRef.isEmpty) {
                            setStateDialog(() {
                              otpInlineError =
                                  'You must tap "Send verification code" first to prove email ownership.';
                            });
                            return;
                          }
                          if (fullName.isEmpty ||
                              studentId.isEmpty ||
                              selectedCourse == null ||
                              selectedYear == null ||
                              selectedSection == null) {
                            messenger.showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Enter full name, student ID, course, year, and section')),
                            );
                            return;
                          }
                        }
                        if (!_isStrongPassword(password)) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                r'Password must be at least 8 characters long, contain at least one uppercase letter, one lowercase letter, one digit, and one special character (!@#$%^&*)',
                              ),
                            ),
                          );
                          return;
                        }
                        final result = await notifier.register(
                          username,
                          password,
                          role,
                          fullName: fullName.isEmpty ? null : fullName,
                          studentId: role == 'student' ? studentId : null,
                          course: role == 'student' ? selectedCourse : null,
                          section: role == 'student' ? selectedSection : null,
                          email: role == 'student' ? email : null,
                          registrationOtp: role == 'student' ? otp : null,
                          registrationOtpRef: role == 'student' ? otpRef : null,
                        );
                        if (!ctx.mounted) return;
                        final err = result.errorMessage;
                        if (err != null) {
                          setStateDialog(() {
                            final lower = err.toLowerCase();
                            if (lower.contains('code') ||
                                lower.contains('otp') ||
                                lower.contains('expired') ||
                                lower.contains('pending')) {
                              otpInlineError = err;
                            } else {
                              otpInlineError = null;
                              messenger.showSnackBar(SnackBar(content: Text(err)));
                            }
                          });
                          return;
                        }
                        sendCooldownTimer?.cancel();
                        if (result.succeeded) {
                          navigator.pop();
                          messenger.showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Account created and email verified. You are now logged in.')),
                          );
                          return;
                        }
                        if (result.isEmailVerificationRequired) {
                          // Student should not reach here (OTP verified pre-register);
                          // This branch is for future faculty pending-email flow.
                          final closed = await _showOtpDialog(
                            ctx,
                            username: result.username ?? username,
                            email: result.email ?? email,
                            expiresInMs: result.expiresInMs,
                            emailSent: result.emailSent ?? false,
                          );
                          if (!ctx.mounted) return;
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                closed == true
                                    ? 'Email verified. You can now log in.'
                                    : 'Account submitted. Verify your email first before logging in.',
                              ),
                            ),
                          );
                          return;
                        }
                        // Faculty / other pending flow.
                        navigator.pop();
                        messenger.showSnackBar(
                          const SnackBar(
                              content:
                                  Text('Account submitted. Wait for admin approval before logging in.')),
                        );
                      },
                      child: const Text('Register'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _showOtpDialog(
    BuildContext context, {
    String? username,
    String? email,
    int? expiresInMs,
    required bool emailSent,
  }) async {
    final codeController = TextEditingController();
    final rootMessenger = MyApp.scaffoldMessengerKey.currentState;
    String? errorText;
    bool isVerifying = false;
    bool isResending = false;
    int? resendCooldownSec;
    Timer? cooldownTimer;
    bool currentEmailSent = emailSent;
    int? currentExpiresInMs = expiresInMs;
    String? resendMessage;

    String expiryLabel(int? ms) {
      if (ms == null) return 'valid for a short time';
      final total = (ms / 1000).round();
      final mins = total ~/ 60;
      final secs = total % 60;
      if (mins <= 0) return 'expires in $secs s';
      if (secs == 0) return 'expires in $mins min';
      return 'expires in $mins min $secs s';
    }

    Timer buildCooldownTimer(
      int seconds,
      bool Function() isMounted,
      void Function(void Function()) refresh,
    ) {
      resendCooldownSec = seconds;
      refresh(() {});
      return Timer.periodic(const Duration(seconds: 1), (t) {
        final next = (resendCooldownSec ?? 0) - 1;
        if (next <= 0) {
          t.cancel();
          resendCooldownSec = 0;
        } else {
          resendCooldownSec = next;
        }
        if (isMounted()) {
          try { refresh(() {}); } catch (_) {}
        } else {
          t.cancel();
        }
      });
    }

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void setDialog(void Function() fn) {
            if (ctx.mounted) setDialogState(fn);
          }

          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) cooldownTimer?.cancel();
            },
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: const [
                  Icon(Icons.mark_email_read_outlined, color: Color(0xFF667eea)),
                  SizedBox(width: 10),
                  Text('Verify Email'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentEmailSent
                        ? 'We sent a 6-digit verification code to ${email ?? 'your email'}.'
                        : 'A 6-digit verification code was generated for ${email ?? username ?? 'your account'}.',
                    style: Theme.of(ctx).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Code ${expiryLabel(currentExpiresInMs)}.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.black54),
                  ),
                  if (!currentEmailSent) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: Colors.amber),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Gmail not configured. Ask your admin for the code in the server logs (look for "[mail][code]").',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: codeController,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                          letterSpacing: 8,
                          fontWeight: FontWeight.w700,
                        ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: InputDecoration(
                      labelText: '6-digit code',
                      hintText: '000000',
                      errorText: errorText,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      counterText: '${codeController.text.length}/6',
                    ),
                    onChanged: (value) {
                      setDialog(() {});
                      if (value.length == 6 && !isVerifying) {
                        WidgetsBinding.instance.addPostFrameCallback((_) async {
                          if (!ctx.mounted) return;
                          setDialog(() {
                            isVerifying = true;
                            errorText = null;
                          });
                          final result = await AuthService.verifyOtp(
                            username: username,
                            email: email,
                            code: value,
                          );
                          if (!ctx.mounted) return;
                          if (result.ok) {
                            cooldownTimer?.cancel();
                            Navigator.of(ctx).pop(true);
                          } else {
                            setDialog(() {
                              isVerifying = false;
                              errorText = result.message ?? 'Invalid code';
                            });
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  if (resendMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        resendMessage!,
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: (isResending || (resendCooldownSec ?? 0) > 0)
                            ? null
                            : () async {
                                setDialog(() {
                                  isResending = true;
                                  errorText = null;
                                  resendMessage = null;
                                });
                                final (ok, message, meta) = await AuthService.resendOtp(
                                  username: username,
                                  email: email,
                                );
                                if (!ctx.mounted) return;
                                if (ok) {
                                  cooldownTimer?.cancel();
                                  cooldownTimer = buildCooldownTimer(60, () => ctx.mounted, setDialog);
                                  final newSent = meta?['emailSent'] == true;
                                  final newExp = meta?['expiresInMs'] as int?;
                                  final base = message ?? 'New code generated';
                                  final snack = newSent
                                      ? '$base — check your Gmail inbox.'
                                      : '$base — check server logs for the code.';
                                  rootMessenger?.showSnackBar(SnackBar(content: Text(snack)));
                                  setDialog(() {
                                    isResending = false;
                                    currentEmailSent = newSent;
                                    currentExpiresInMs = newExp ?? currentExpiresInMs;
                                    resendMessage = snack;
                                  });
                                  codeController.clear();
                                } else {
                                  setDialog(() {
                                    isResending = false;
                                    if (message != null && message.toLowerCase().contains('cooldown')) {
                                      resendCooldownSec = 60;
                                    }
                                    errorText = message ?? 'Could not resend';
                                  });
                                }
                              },
                        child: isResending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                resendCooldownSec != null && resendCooldownSec! > 0
                                    ? 'Resend code (${resendCooldownSec}s)'
                                    : 'Resend code',
                              ),
                      ),
                      TextButton(
                        onPressed: () {
                          cooldownTimer?.cancel();
                          Navigator.of(ctx).pop(false);
                        },
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: (isVerifying || codeController.text.length != 6)
                      ? null
                      : () async {
                          setDialog(() {
                            isVerifying = true;
                            errorText = null;
                          });
                          final result = await AuthService.verifyOtp(
                            username: username,
                            email: email,
                            code: codeController.text.trim(),
                          );
                          if (!ctx.mounted) return;
                          if (result.ok) {
                            cooldownTimer?.cancel();
                            Navigator.of(ctx).pop(true);
                          } else {
                            setDialog(() {
                              isVerifying = false;
                              errorText = result.message ?? 'Invalid code';
                            });
                          }
                        },
                  child: isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Verify'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showResetPasswordDialog(BuildContext context) async {
    final usernameController = TextEditingController(text: _usernameController.text.trim());
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Reset Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email or Username',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPasswordController,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  suffixIcon: IconButton(
                    tooltip: obscureNew ? 'Show password' : 'Hide password',
                    onPressed: () => setStateDialog(() => obscureNew = !obscureNew),
                    icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPasswordController,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  suffixIcon: IconButton(
                    tooltip: obscureConfirm ? 'Show password' : 'Hide password',
                    onPressed: () => setStateDialog(() => obscureConfirm = !obscureConfirm),
                    icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final messenger = MyApp.scaffoldMessengerKey.currentState ??
                    ScaffoldMessenger.of(context);
                final dialogNavigator = Navigator.of(dialogContext);
                final username = usernameController.text.trim();
                final newPassword = newPasswordController.text;
                final confirmPassword = confirmPasswordController.text;

                if (username.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }
                if (newPassword != confirmPassword) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Password confirmation does not match')),
                  );
                  return;
                }
                if (!_isStrongPassword(newPassword)) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        r'Password must be at least 8 characters long, contain at least one uppercase letter, one lowercase letter, one digit, and one special character (!@#$%^&*)',
                      ),
                    ),
                  );
                  return;
                }

                try {
                  await ApiService.resetPassword(username, newPassword);
                  dialogNavigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Password reset successful. You can login now.')),
                  );
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
