import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart' show MyApp, buildAppBackground, AppThemeAssets;
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart' show AuthService;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _canSubmit = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _identifierController.addListener(_onIdentifierChanged);
    _passwordController.addListener(_syncCanSubmit);
    _syncCanSubmit();
  }

  void _onIdentifierChanged() {
    _syncCanSubmit();
    // Rebuild on identifier change so the sign-in button state updates.
    setState(() {});
  }

  void _syncCanSubmit() {
    final id = _identifierController.text.trim();
    final passwordOk = _passwordController.text.isNotEmpty;
    final next = id.isNotEmpty && passwordOk;
    if (next == _canSubmit) return;
    setState(() => _canSubmit = next);
  }

  bool _isStrongPassword(String password) {
    final strongPasswordRegex = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*[0-9])(?=.*[!@#$%^&*])(?=.{8,})');
    return strongPasswordRegex.hasMatch(password);
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final authNotifier = ref.read(authProvider.notifier);

    return Scaffold(
      body: buildAppBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0x22000000),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Image.asset(
                              AppThemeAssets.lccLogo,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.school,
                                size: 40,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Colors.white, Color(0xFFBFDBFE)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        'Attendify',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                              color: Colors.white,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Sign in to continue',
                      style: TextStyle(color: Color(0xFFCFE0FF), fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    Card(
                      elevation: 8,
                      shadowColor: const Color(0x33000000),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: _identifierController,
                              keyboardType: TextInputType.emailAddress,
                              autocorrect: false,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.username],
                              decoration: const InputDecoration(
                                labelText: 'ID or Email',
                                prefixIcon: Icon(Icons.person_outline),
                                helperText: 'Use your Student ID, Professor ID, or email address.',
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
                                prefixIcon: const Icon(Icons.lock_outline),
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
                                            _identifierController.text,
                                            _passwordController.text,
                                          );
                                      AuthActionResult result = await doLogin();
                                      if (!ctx.mounted) return;
                                      if (result.succeeded) return;
                                      if (result.isPendingAdminApproval) {
                                        final ok = await showDialog<bool>(
                                          context: ctx,
                                          barrierDismissible: false,
                                          builder: (context) => AlertDialog(
                                            icon: const Icon(Icons.verified_user_outlined, size: 40),
                                            title: const Text('Professor Account Pending Approval'),
                                            content: SingleChildScrollView(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    result.errorMessage ??
                                                        'Your professor account is still pending approval by an administrator. You will be able to sign in once the admin approves your registration.',
                                                  ),
                                                  const SizedBox(height: 10),
                                                  if ((result.username ?? '').isNotEmpty)
                                                    Text.rich(
                                                      TextSpan(
                                                        children: [
                                                          const TextSpan(
                                                            text: 'Username: ',
                                                            style: TextStyle(fontWeight: FontWeight.bold),
                                                          ),
                                                          TextSpan(text: result.username),
                                                        ],
                                                      ),
                                                    ),
                                                  if ((result.email ?? '').isNotEmpty)
                                                    Padding(
                                                      padding: const EdgeInsets.only(top: 4),
                                                      child: Text.rich(
                                                        TextSpan(
                                                          children: [
                                                            const TextSpan(
                                                              text: 'Email: ',
                                                              style: TextStyle(fontWeight: FontWeight.bold),
                                                            ),
                                                            TextSpan(text: result.email),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Tip: Contact your school administrator or department head to speed up approval.',
                                                    style: TextStyle(color: Colors.black54, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            actions: [
                                              FilledButton.icon(
                                                onPressed: () => Navigator.pop(context, true),
                                                icon: const Icon(Icons.refresh),
                                                label: const Text('Try again'),
                                              ),
                                              OutlinedButton(
                                                onPressed: () => Navigator.pop(context, false),
                                                child: const Text('Back to login'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (!ctx.mounted) return;
                                        if (ok == true) {
                                          final retry = await doLogin();
                                          if (!ctx.mounted) return;
                                          if (retry.succeeded) return;
                                          final msg = retry.isPendingAdminApproval
                                              ? 'Still pending. Please wait for your administrator to approve your account, then tap Try again.'
                                              : (retry.errorMessage ?? 'Login failed');
                                          messenger.showSnackBar(SnackBar(content: Text(msg)));
                                        }
                                        return;
                                      }
                                      if (result.isEmailVerificationRequired) {
                                        final closed = await _showOtpDialog(
                                          ctx,
                                          username: result.username ?? _identifierController.text.trim(),
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
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (authState.isLoading || !_canSubmit)
                                    ? null
                                    : () async {
                                        final ctx = context;
                                        final messenger = MyApp.scaffoldMessengerKey.currentState ??
                                            ScaffoldMessenger.of(ctx);
                                        Future<AuthActionResult> doLogin() => authNotifier.login(
                                              _identifierController.text,
                                              _passwordController.text,
                                            );
                                        AuthActionResult result = await doLogin();
                                        if (!ctx.mounted) return;
                                        if (result.succeeded) return;
                                        if (result.isPendingAdminApproval) {
                                          final ok = await showDialog<bool>(
                                            context: ctx,
                                            barrierDismissible: false,
                                            builder: (context) => AlertDialog(
                                              icon: const Icon(Icons.verified_user_outlined, size: 40),
                                              title: const Text('Professor Account Pending Approval'),
                                              content: SingleChildScrollView(
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      result.errorMessage ??
                                                          'Your professor account is still pending approval by an administrator. You will be able to sign in once the admin approves your registration.',
                                                    ),
                                                    const SizedBox(height: 10),
                                                    if ((result.username ?? '').isNotEmpty)
                                                      Text.rich(
                                                        TextSpan(
                                                          children: [
                                                            const TextSpan(
                                                              text: 'Username: ',
                                                              style: TextStyle(fontWeight: FontWeight.bold),
                                                            ),
                                                            TextSpan(text: result.username),
                                                          ],
                                                        ),
                                                      ),
                                                    if ((result.email ?? '').isNotEmpty)
                                                      Padding(
                                                        padding: const EdgeInsets.only(top: 4),
                                                        child: Text.rich(
                                                          TextSpan(
                                                            children: [
                                                              const TextSpan(
                                                                text: 'Email: ',
                                                                style: TextStyle(fontWeight: FontWeight.bold),
                                                              ),
                                                              TextSpan(text: result.email),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    const SizedBox(height: 8),
                                                    const Text(
                                                      'Tip: Contact your school administrator or department head to speed up approval.',
                                                      style: TextStyle(color: Colors.black54, fontSize: 12),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              actions: [
                                                FilledButton.icon(
                                                  onPressed: () => Navigator.pop(context, true),
                                                  icon: const Icon(Icons.refresh),
                                                  label: const Text('Try again'),
                                                ),
                                                OutlinedButton(
                                                  onPressed: () => Navigator.pop(context, false),
                                                  child: const Text('Back to login'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (!ctx.mounted) return;
                                          if (ok == true) {
                                            final retry = await doLogin();
                                            if (!ctx.mounted) return;
                                            if (retry.succeeded) return;
                                            final msg = retry.isPendingAdminApproval
                                                ? 'Still pending. Please wait for your administrator to approve your account, then tap Try again.'
                                                : (retry.errorMessage ?? 'Login failed');
                                            messenger.showSnackBar(SnackBar(content: Text(msg)));
                                          }
                                          return;
                                        }
                                        if (result.isEmailVerificationRequired) {
                                          final closed = await _showOtpDialog(
                                            ctx,
                                            username: result.username ?? _identifierController.text.trim(),
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
                                    : const Text('Sign in'),
                              ),
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
                  ],
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
    final usernameController = TextEditingController(text: _identifierController.text);
    final passwordController = TextEditingController(text: _passwordController.text);
    final fullNameController = TextEditingController();
    final studentIdController = TextEditingController();
    final emailController = TextEditingController(text: _identifierController.text.trim());
    final otpController = TextEditingController();
    const courses = [
      'Bachelor of Science in Criminology',
      'Bachelor of Science in Information System',
      'Bachelor of Science in Psychology',
      'Bachelor of Science in Accounting Information System',
      'Bachelor of Secondary Education',
      'Bachelor of Science in Accountancy',
      'Bachelor of Science in Civil Engineering',
      'Bachelor of Science in Business Administration',
      'Communication Arts Division',
    ];
    const Map<String, String> courseCodes = {
      'Bachelor of Science in Criminology': 'BSC',
      'Bachelor of Science in Information System': 'BSIS',
      'Bachelor of Science in Psychology': 'BSP',
      'Bachelor of Science in Accounting Information System': 'BSAIS',
      'Bachelor of Secondary Education': 'BSED',
      'Bachelor of Science in Accountancy': 'BSA',
      'Bachelor of Science in Civil Engineering': 'BSCE',
      'Bachelor of Science in Business Administration': 'BSBA',
      'Communication Arts Division': 'CAD',
    };
    String studentType = 'regular'; // 'regular' (one course) or 'irregular' (many)
    final Set<String> selectedStudentCourses = {};
    String? selectedCourse;
    int? selectedYear;
    String? selectedSection;
    final Set<String> selectedHandledCourseCodes = {};
    const List<MapEntry<String, String>> handledCourseOptions = [
      MapEntry('BSC', 'Bachelor of Science in Criminology'),
      MapEntry('BSIS', 'Bachelor of Science in Information System'),
      MapEntry('BSP', 'Bachelor of Science in Psychology'),
      MapEntry('BSAIS', 'Bachelor of Science in Accounting Information System'),
      MapEntry('BSED', 'Bachelor of Secondary Education'),
      MapEntry('BSA', 'Bachelor of Science in Accountancy'),
      MapEntry('BSCE', 'Bachelor of Science in Civil Engineering'),
      MapEntry('BSBA', 'Bachelor of Science in Business Administration'),
      MapEntry('CAD', 'Communication Arts Division'),
    ];
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
    // ---- Inline banner state for validation errors inside dialog ----
    String? submitBannerError;
    final passwordFieldKey = GlobalKey();
    final scrollController = ScrollController();

    // ---- Clear any leftover snackbars from Login page ----
    final rootMessenger = MyApp.scaffoldMessengerKey.currentState;
    rootMessenger?.clearSnackBars();

    List<String> buildSections() {
      if (selectedYear == null) return const [];
      final String code;
      if (studentType == 'irregular') {
        code = 'IRREG';
      } else {
        if (selectedCourse == null) return const [];
        code = courseCodes[selectedCourse!] ?? 'BS';
      }
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

    void scrollToPassword() {
      final mountedRoute = ModalRoute.of(context);
      final localController = scrollController;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!(mountedRoute?.isActive ?? false)) return;
        final targetCtx = passwordFieldKey.currentContext;
        final targetHasClients = localController.hasClients;
        final targetMax = targetHasClients ? localController.position.maxScrollExtent : 0.0;
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!(mountedRoute?.isActive ?? false)) return;
        try {
          if (targetCtx != null) {
            final elementOk = targetCtx;
            // ignore: use_build_context_synchronously
            await Scrollable.ensureVisible(elementOk,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                alignment: 0.1);
          } else if (targetHasClients) {
            localController.animateTo(
              targetMax * 0.25,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
            );
          }
        } catch (_) {}
      });
    }

    showDialog<void>(
      context: context,
      builder: (context) {
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
                refresh(() {
                  submitBannerError = null;
                  emailInlineError = 'Enter a valid Gmail address (e.g. name@gmail.com).';
                });
                return;
              }
              refresh(() {
                sendingOtp = true;
                emailInlineError = null;
                submitBannerError = null;
              });
              final res = await notifier.sendRegistrationOtp(email);
              if (!(routeActive?.isActive ?? false)) return;
              if (res.ok) {
                startSendCooldown(60);
                pendingOtpRef = res.ref;
                pendingOtpEmail = res.email ?? email.toLowerCase();
                pendingOtpExpiresInMs = res.expiresInMs ?? 10 * 60 * 1000;
                lastEmailSent = res.emailSent;
                rootMessenger?.clearSnackBars();
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
                  submitBannerError = null;
                });
                scrollToPassword();
              } else {
                refresh(() {
                  sendingOtp = false;
                  submitBannerError = null;
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
                    maxHeight: MediaQuery.of(context).size.height * 0.78,
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (submitBannerError != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.error_outline, size: 18, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    submitBannerError!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: Colors.red.shade900, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // -------- Role selector (Professor accounts are created by an administrator) --------
                        DropdownButtonFormField<String>(
                          initialValue: role,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Role'),
                          items: const [
                            DropdownMenuItem(value: 'student', child: Text('Student')),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setStateDialog(() {
                              role = value;
                              selectedCourse = null;
                              selectedYear = null;
                              selectedSection = null;
                              submitBannerError = null;
                              if (role != 'faculty') {
                                selectedHandledCourseCodes.clear();
                              }
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
                                          ? 'Code sent to ${pendingOtpEmail ?? emailController.text.trim()}. Valid ${expiryLabel(pendingOtpExpiresInMs)}. Scroll below to fill account form.'
                                          : 'Code generated for ${pendingOtpEmail ?? emailController.text.trim()}. Check server logs: "[mail][code]". Valid ${expiryLabel(pendingOtpExpiresInMs)}. Scroll below to fill account form.',
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
                            Container(
                              key: passwordFieldKey,
                              child: TextField(
                                controller: passwordController,
                                obscureText: obscureRegisterPassword,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
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
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: fullNameController,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: studentIdController,
                              keyboardType: TextInputType.text,
                              decoration: const InputDecoration(
                                labelText: 'Student ID',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.category_outlined, size: 20),
                                const SizedBox(width: 8),
                                const Text('Student Type',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                SegmentedButton<String>(
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(value: 'regular', label: Text('Regular')),
                                    ButtonSegment(value: 'irregular', label: Text('Irregular')),
                                  ],
                                  selected: {studentType},
                                  onSelectionChanged: (set) {
                                    if (set.isEmpty) return;
                                    setStateDialog(() {
                                      studentType = set.first;
                                      selectedCourse = null;
                                      selectedStudentCourses.clear();
                                      selectedSection = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (studentType == 'regular')
                              DropdownButtonFormField<String>(
                                initialValue: selectedCourse,
                                isExpanded: true,
                                menuMaxHeight: 320,
                                decoration: const InputDecoration(
                                  labelText: 'Course',
                                  prefixIcon: Icon(Icons.school_outlined),
                                ),
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
                              )
                            else ...[
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Courses (select one or more):',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey.shade300),
                                  borderRadius: BorderRadius.circular(12),
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                                constraints: const BoxConstraints(maxHeight: 220),
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: [
                                      for (final c in courses)
                                        CheckboxListTile.adaptive(
                                          dense: true,
                                          value: selectedStudentCourses.contains(c),
                                          title: Text(
                                            c,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          onChanged: (v) => setStateDialog(() {
                                            if (v == true) {
                                              selectedStudentCourses.add(c);
                                            } else {
                                              selectedStudentCourses.remove(c);
                                            }
                                            selectedSection = null;
                                          }),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              initialValue: selectedYear,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Year Level',
                                prefixIcon: Icon(Icons.calendar_today_outlined),
                              ),
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
                              decoration: const InputDecoration(
                                labelText: 'Section',
                                prefixIcon: Icon(Icons.group_outlined),
                              ),
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
                            const SizedBox(height: 8),
                          ],
                        ] else ...[
                          // -------------- FACULTY / PROFESSOR flow --------------
                          TextField(
                            controller: usernameController,
                            decoration: const InputDecoration(labelText: 'Username'),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: passwordController,
                            key: passwordFieldKey,
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
                          const SizedBox(height: 16),
                          const Text(
                            'Courses you handle (select at least one):',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                              color: Theme.of(context).colorScheme.surface,
                            ),
                            child: Column(
                              children: [
                                for (final opt in handledCourseOptions)
                                  CheckboxListTile.adaptive(
                                    value: selectedHandledCourseCodes.contains(opt.key),
                                    title: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary
                                                .withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.30),
                                            ),
                                          ),
                                          child: Text(
                                            opt.key,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              letterSpacing: 0.4,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            opt.value,
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                    controlAffinity: ListTileControlAffinity.leading,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 2),
                                    dense: true,
                                    onChanged: (v) {
                                      setStateDialog(() {
                                        if (v == true) {
                                          selectedHandledCourseCodes.add(opt.key);
                                        } else {
                                          selectedHandledCourseCodes.remove(opt.key);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                          if (selectedHandledCourseCodes.isEmpty && submitBannerError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '⚠ Pick the course(s) you teach.',
                                style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                              ),
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
                        submitBannerError = null;
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
                        final messenger = rootMessenger ?? ScaffoldMessenger.of(ctx);
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
                          if (role == 'student' && username.isEmpty) {
                            setStateDialog(() {
                              studentStage = 1;
                              submitBannerError =
                                  'Enter your Gmail first, then tap "Send verification code".';
                              emailInlineError = 'Enter a valid Gmail address.';
                            });
                          } else {
                            setStateDialog(() {
                              submitBannerError = role == 'student'
                                  ? 'Enter your account password (and scroll down if you cannot see it).'
                                  : 'Enter username and password.';
                            });
                          }
                          scrollToPassword();
                          return;
                        }
                        if (role == 'student') {
                          if (otp == null || otp.length != 6) {
                            setStateDialog(() {
                              otpInlineError = 'Enter the 6-digit code we sent to your Gmail.';
                              submitBannerError = 'Enter the 6-digit verification code above.';
                            });
                            return;
                          }
                          if (otpRef == null || otpRef.isEmpty) {
                            setStateDialog(() {
                              otpInlineError =
                                  'You must tap "Send verification code" first to prove email ownership.';
                              submitBannerError =
                                  'Go back to Step 1 (tap "Change email") and tap Send verification code first.';
                            });
                            return;
                          }
                          final hasCourseSelection = studentType == 'irregular'
                              ? selectedStudentCourses.isNotEmpty
                              : selectedCourse != null;
                          if (fullName.isEmpty ||
                              studentId.isEmpty ||
                              !hasCourseSelection ||
                              selectedYear == null ||
                              selectedSection == null) {
                            setStateDialog(() {
                              submitBannerError = studentType == 'irregular'
                                  ? 'Fill every field below: Full name, Student ID, at least one Course, Year Level, Section.'
                                  : 'Fill every field below: Full name, Student ID, Course, Year Level, Section.';
                            });
                            scrollToPassword();
                            return;
                          }
                        }
                        if (role == 'faculty') {
                          if (fullName.isEmpty) {
                            setStateDialog(() {
                              submitBannerError = 'Enter your full name.';
                            });
                            return;
                          }
                          if (selectedHandledCourseCodes.isEmpty) {
                            setStateDialog(() {
                              submitBannerError =
                                  'Pick at least one course you handle (tap the checkboxes above).';
                            });
                            return;
                          }
                        }
                        if (!_isStrongPassword(password)) {
                          setStateDialog(() {
                            submitBannerError =
                                r'Password must be 8+ chars: 1 uppercase, 1 lowercase, 1 digit, 1 special char (!@#$%^&*).';
                          });
                          scrollToPassword();
                          return;
                        }
                        setStateDialog(() => submitBannerError = null);
                        final result = await notifier.register(
                          username,
                          password,
                          role,
                          fullName: fullName.isEmpty ? null : fullName,
                          studentId: role == 'student' ? studentId : null,
                          studentType: role == 'student' ? studentType : null,
                          course: role == 'student' && studentType == 'regular' ? selectedCourse : null,
                          courses: role == 'student' && studentType == 'irregular'
                              ? selectedStudentCourses.toList()
                              : null,
                          section: role == 'student' ? selectedSection : null,
                          email: role == 'student' ? email : null,
                          registrationOtp: role == 'student' ? otp : null,
                          registrationOtpRef: role == 'student' ? otpRef : null,
                          handledCourses: role == 'faculty'
                              ? selectedHandledCourseCodes
                                  .map((code) {
                                    // Registration dialog checkboxes accumulate SHORT course codes
                                    // (BSP, BSC, BSIS, ...). Canonical wire format = FULL degree
                                    // names (ALL_COURSES on server, kCourseShort keys on client).
                                    // Convert short → full before sending to AuthNotifier / server.
                                    for (final entry in handledCourseOptions) {
                                      if (entry.key == code) return entry.value;
                                    }
                                    return code;
                                  })
                                  .toList()
                              : null,
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
                              submitBannerError =
                                  'Fix the verification code above (it may be wrong or expired).';
                            } else {
                              otpInlineError = null;
                              submitBannerError = err;
                              messenger.clearSnackBars();
                              messenger.showSnackBar(SnackBar(content: Text(err)));
                            }
                          });
                          return;
                        }
                        sendCooldownTimer?.cancel();
                        if (result.succeeded) {
                          navigator.pop();
                          messenger.clearSnackBars();
                          messenger.showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Account created and email verified. You are now logged in.')),
                          );
                          return;
                        }
                        if (result.isEmailVerificationRequired) {
                          final closed = await _showOtpDialog(
                            ctx,
                            username: result.username ?? username,
                            email: result.email ?? email,
                            expiresInMs: result.expiresInMs,
                            emailSent: result.emailSent ?? false,
                          );
                          if (!ctx.mounted) return;
                          navigator.pop();
                          messenger.clearSnackBars();
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
                        messenger.clearSnackBars();
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
    final seededIdentifier = _identifierController.text.trim();
    final emailController = TextEditingController(
      text: seededIdentifier.contains('@') ? seededIdentifier : '',
    );
    final otpController = TextEditingController();
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;
    int stage = 1;
    bool sending = false;
    bool submitting = false;
    String? resetRef;
    int cooldownSec = 0;
    Timer? cooldownTimer;
    final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

    String stepLabel(int value) {
      switch (value) {
        case 1:
          return 'Step 1 of 3: Verify your email address';
        case 2:
          return 'Step 2 of 3: Enter the OTP and your current password';
        case 3:
          return 'Step 3 of 3: Enter and confirm your new password';
        default:
          return '';
      }
    }

    String friendlyResetError(Object error) {
      final raw = error.toString().replaceFirst('Exception: ', '').trim();
      if (raw.contains('Cannot POST /api/request-password-reset-otp')) {
        return 'The password reset service is not available on the server yet. Please redeploy the backend first.';
      }
      if (raw.contains('Cannot POST /api/reset-password')) {
        return 'The reset password service is not available on the server yet. Please redeploy the backend first.';
      }
      return raw;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final messenger = MyApp.scaffoldMessengerKey.currentState ??
              ScaffoldMessenger.of(context);

          void startCooldown(int secs) {
            cooldownSec = secs;
            cooldownTimer?.cancel();
            cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
              if (!(ModalRoute.of(context)?.isActive ?? false)) {
                t.cancel();
                return;
              }
              final next = cooldownSec - 1;
              if (next <= 0) {
                cooldownSec = 0;
                t.cancel();
              } else {
                cooldownSec = next;
              }
              setStateDialog(() {});
            });
          }

          Future<void> sendCode() async {
            final email = emailController.text.trim().toLowerCase();
            if (email.isEmpty) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter your email first')),
              );
              return;
            }
            if (!emailRegex.hasMatch(email)) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter a valid email address')),
              );
              return;
            }
            setStateDialog(() => sending = true);
            try {
              final res = await ApiService.requestPasswordResetOtp(email);
              if (!context.mounted) return;
              resetRef = res['ref']?.toString();
              setStateDialog(() {
                sending = false;
                stage = 2;
              });
              startCooldown(60);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    res['message']?.toString() ??
                        'We emailed a 6-digit code to $email. Enter it below.',
                  ),
                ),
              );
            } catch (e) {
              if (!context.mounted) return;
              setStateDialog(() => sending = false);
              messenger.showSnackBar(SnackBar(content: Text(friendlyResetError(e))));
            }
          }

          void continueToNewPassword() {
            final otp = otpController.text.trim();
            final currentPassword = currentPasswordController.text;
            if (otp.length != 6) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter the 6-digit code sent to your email')),
              );
              return;
            }
            if (currentPassword.isEmpty) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter your current password')),
              );
              return;
            }
            setStateDialog(() => stage = 3);
          }

          Future<void> submitReset() async {
            final dialogNavigator = Navigator.of(dialogContext);
            final email = emailController.text.trim().toLowerCase();
            final otp = otpController.text.trim();
            final currentPassword = currentPasswordController.text;
            final newPassword = newPasswordController.text;
            final confirmPassword = confirmPasswordController.text;

            if (!emailRegex.hasMatch(email)) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter a valid email address')),
              );
              return;
            }
            if (otp.length != 6) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter the 6-digit code sent to your email')),
              );
              return;
            }
            if (currentPassword.isEmpty) {
              messenger.showSnackBar(
                const SnackBar(content: Text('Enter your current password')),
              );
              return;
            }
            if (newPassword.isEmpty || confirmPassword.isEmpty) {
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

            setStateDialog(() => submitting = true);
            try {
              await ApiService.resetPassword(
                email,
                newPassword,
                currentPassword: currentPassword,
                resetOtp: otp,
                resetOtpRef: resetRef ?? '',
              );
              cooldownTimer?.cancel();
              if (!context.mounted) return;
              dialogNavigator.pop();
              messenger.showSnackBar(
                const SnackBar(content: Text('Password reset successful. You can sign in now.')),
              );
            } catch (e) {
              if (!context.mounted) return;
              setStateDialog(() => submitting = false);
              messenger.showSnackBar(
                SnackBar(content: Text(friendlyResetError(e))),
              );
            }
          }

          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Reset Password'),
                const SizedBox(height: 4),
                Text(
                  stepLabel(stage),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (stage == 1) ...[
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.alternate_email),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'We will email a 6-digit verification code to the address registered on your account.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: sending ? null : sendCode,
                        icon: sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_outlined, size: 18),
                        label: Text(sending ? 'Sending…' : 'Send verification code'),
                      ),
                    ),
                  ] else if (stage == 2) ...[
                    Text(
                      'We sent a 6-digit code to ${emailController.text.trim().toLowerCase()}. Enter the code and your current password to continue.',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Verification code (OTP)',
                        prefixIcon: Icon(Icons.password_outlined),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        suffixIcon: IconButton(
                          tooltip: obscureCurrent ? 'Show password' : 'Hide password',
                          onPressed: () => setStateDialog(() => obscureCurrent = !obscureCurrent),
                          icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: (sending || cooldownSec > 0) ? null : sendCode,
                        child: Text(
                          cooldownSec > 0 ? 'Resend code in ${cooldownSec}s' : 'Resend code',
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Choose a strong new password for ${emailController.text.trim().toLowerCase()}.',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 12),
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
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              if (stage == 2)
                TextButton(
                  onPressed: sending ? null : () => setStateDialog(() => stage = 1),
                  child: const Text('Back'),
                ),
              if (stage == 3)
                TextButton(
                  onPressed: submitting ? null : () => setStateDialog(() => stage = 2),
                  child: const Text('Back'),
                ),
              if (stage == 2)
                ElevatedButton(
                  onPressed: sending ? null : continueToNewPassword,
                  child: const Text('Continue'),
                ),
              if (stage == 3)
                ElevatedButton(
                  onPressed: submitting ? null : submitReset,
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Reset Password'),
                ),
            ],
          );
        },
      ),
    );
    cooldownTimer?.cancel();
  }
}
