import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../main.dart' show AppThemeAssets, AppColors;
import '../providers/auth_provider.dart';
import '../services/event_provider.dart';
import '../services/attendance_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../models/event.dart';
import '../models/attendance.dart';
import '../config.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    if (user == null) {
      return const SizedBox.shrink();
    }
    if (user.role == 'admin') {
      return AdminHomeScreen(user: user);
    }
    if (user.role == 'faculty') {
      if (!user.isApproved) {
        return FacultyPendingApprovalScreen(user: user);
      }
      return FacultyHomeScreen(user: user);
    }
    return StudentHomeScreen(user: user);
  }
}

Future<void> _openStandaloneScanner(BuildContext context, User user) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _StandaloneQrScannerScreen(user: user),
    ),
  );
}

const int _kPosterMaxSidePx = 4096;
const int _kPosterMaxBytes = 5250 * 1024; // 5.25 MB raw bytes (target ≈ 5 MB)
const int _kPosterMaxBase64Chars = 7 * 1024 * 1024; // 7 MB base64 (raw → 4/3 expansion)

const List<String> kCoursesList = [
  'Bachelor of Science in Criminology',
  'Bachelor of Science in Information System',
  'Bachelor of Science in Psychology',
  'Bachelor of Science in Accounting Information System',
  'Bachelor of Secondary Education',
  'Bachelor of Science in Accountancy',
];
const Map<String, String> kCourseShort = {
  'Bachelor of Science in Criminology': 'BSC',
  'Bachelor of Science in Information System': 'BSIS',
  'Bachelor of Science in Psychology': 'BSP',
  'Bachelor of Science in Accounting Information System': 'BSAIS',
  'Bachelor of Secondary Education': 'BSED',
  'Bachelor of Science in Accountancy': 'BSA',
};

Future<Uint8List> _compressPosterBytes(Uint8List raw) async {
  // Passthrough: preserve original quality, dimensions, aspect ratio, and visual appearance.
  // No crop, no stretch, no resample. Size is enforced only via hard caps in the picker handler.
  return raw;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({required this.user, required this.ref});

  final User user;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final initials = (user.fullName.isNotEmpty ? user.fullName : user.username)
        .split(RegExp(r'\s+'))
        .map((s) => s.isEmpty ? '' : s[0].toUpperCase())
        .take(2)
        .join();
    return Drawer(
      width: 280,
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryStart, Color(0xFF2563eb), AppColors.primaryEnd],
                ),
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    child: Text(
                      initials.isEmpty ? 'U' : initials,
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.fullName.isEmpty ? user.username : user.fullName,
                          style: textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.2,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${user.role.toUpperCase()} • ${(user.studentId.isNotEmpty && user.role == 'student') ? user.studentId : user.username}',
                          style: textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (user.role == 'student')
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_outlined),
                title: const Text('Scan QR', style: TextStyle(fontWeight: FontWeight.w700)),
                onTap: () {
                  Navigator.pop(context);
                  _openStandaloneScanner(context, user);
                },
              ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                _openSettingsSheet(context, ref, user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Instructions'),
              onTap: () {
                Navigator.pop(context);
                _showInstructionsDialog(context, user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              onTap: () {
                Navigator.pop(context);
                _showAboutUsDialog(context);
              },
            ),
            const Spacer(),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFB3261E)),
              title: const Text('Logout',
                  style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(context);
                ref.read(authProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

void _openSettingsSheet(BuildContext context, WidgetRef ref, User user) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Instructions'),
              subtitle: Text('How to use the app as ${user.role}.'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showInstructionsDialog(context, user);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              subtitle: const Text('App details and purpose.'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAboutUsDialog(context);
              },
            ),
            const Divider(height: 8),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFFB3261E)),
              title: const Text('Logout', style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
              onTap: () {
                Navigator.pop(sheetContext);
                ref.read(authProvider.notifier).logout();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

void _showInstructionsDialog(BuildContext context, User user) {
  final title = switch (user.role) {
    'admin' => 'Admin Instructions',
    'faculty' => 'Faculty Instructions',
    _ => 'Student Instructions',
  };
  final text = switch (user.role) {
    'admin' =>
      '1. Create and manage events.\n'
          '2. Show event QR for attendance.\n'
          '3. Manage users and reports.\n'
          '4. Keep only trusted admin accounts.',
    'faculty' =>
      '1. Open Events tab and check active events.\n'
          '2. In Attendance, monitor your handled records.\n'
          '3. During scanning, select faculty correctly for check-in/check-out.',
    _ =>
      '1. Open Events tab to view event posters & details.\n'
          '2. Tap an event, then scroll to "Scan QR for Attendance" section.\n'
          '3. Quick access: open drawer (top-left ☰) → Scan QR anytime.\n'
          '4. Select faculty for check-in/check-out during scan.\n'
          '5. Review logs in My Attendance tab.',
  };

  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

void _showAboutUsDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (context) {
      final textTheme = Theme.of(context).textTheme;
      return AlertDialog(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.groups_2_outlined,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            const Text('About Us'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 84,
                  height: 84,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/lcc.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ATTENDIFY: A QR CODE BASED ATTENDANCE TRACKING SYSTEM FOR EFFICIENT SCHOOL EVENT MANAGEMENT AT LA CONCEPCION COLLEGE',
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Team Roles',
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _RoleLine(
                role: 'Programmer',
                name: 'Mark Keneth M Ilagan',
                highlight: true,
              ),
              const SizedBox(height: 4),
              const _RoleLine(
                role: 'Project Manager',
                name: 'Tirso Jr A. Dela Pena',
              ),
              const SizedBox(height: 4),
              const _RoleLine(
                role: 'Document Specialist',
                name: 'Chelsea Rayne Glynese M. Olavides',
              ),
              const SizedBox(height: 4),
              const _RoleLine(
                role: 'Document Specialist',
                name: 'Jellamae T. Base',
              ),
              const SizedBox(height: 4),
              const _RoleLine(
                role: 'System Analyst',
                name: 'Ayessah May G. Santelices',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _RoleLine extends StatelessWidget {
  const _RoleLine({
    required this.role,
    required this.name,
    this.highlight = false,
  });

  final String role;
  final String name;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final text = '$role - $name';
    if (!highlight) return Text(text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (context) {
          return Scaffold(
            drawer: _AppDrawer(user: user, ref: ref),
            extendBody: false,
            appBar: AppBar(
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Administrator'),
                  Text(
                    user.username,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              actions: const [
                SizedBox(width: 8),
              ],
              flexibleSpace: const _AppBarGradientBg(),
              bottom: const TabBar(
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                tabs: [
                  Tab(icon: Icon(Icons.event), text: 'Events'),
                  Tab(icon: Icon(Icons.list_alt), text: 'Attendance'),
                  Tab(icon: Icon(Icons.summarize), text: 'Reports'),
                  Tab(icon: Icon(Icons.manage_accounts), text: 'Users'),
                ],
              ),
            ),
            body: const _TabBackground(
              child: TabBarView(
                children: [
                  AdminEventsTab(),
                  AdminAttendanceTab(),
                  AdminReportsTab(),
                  AdminUsersTab(),
                ],
              ),
            ),
            floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
            floatingActionButton: Consumer(
              builder: (context, ref, _) {
                return _AdminEventsFab(builderContext: context, ref: ref);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AdminEventsFab extends StatelessWidget {
  const _AdminEventsFab({required this.builderContext, required this.ref});
  final BuildContext builderContext;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final controller = DefaultTabController.of(builderContext);
    return AnimatedBuilder(
      animation: controller.animation ?? const AlwaysStoppedAnimation(0),
      builder: (ctx, child) {
        final showFab = controller.index == 0;
        return AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          offset: showFab ? const Offset(0, 0) : const Offset(0, 1.6),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: showFab ? 1.0 : 0.0,
            child: FloatingActionButton.extended(
              heroTag: 'admin_add_event_fab',
              elevation: 6,
              onPressed: showFab ? () => _showEventDialog(ctx, ref) : null,
              backgroundColor: AppColors.primaryStart,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Event', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        );
      },
    );
  }
}

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: _AppDrawer(user: user, ref: ref),
        extendBody: false,
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Student'),
              Text(
                user.studentId.isNotEmpty ? user.studentId : user.username,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          forceMaterialTransparency: true,
          elevation: 0,
          actions: const [
            SizedBox(width: 8),
          ],
          flexibleSpace: const _AppBarGradientBg(),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.event_available_outlined), text: 'Events'),
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR'),
              Tab(icon: Icon(Icons.history), text: 'My Attendance'),
            ],
          ),
        ),
        body: _TabBackground(
          child: TabBarView(
            children: [
              StudentEventsTab(user: user),
              StudentScannerTab(user: user),
              StudentAttendanceTab(user: user),
            ],
          ),
        ),
      ),
    );
  }
}

class FacultyHomeScreen extends ConsumerWidget {
  const FacultyHomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: _AppDrawer(user: user, ref: ref),
        extendBody: false,
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Faculty'),
              Text(
                user.fullName.isEmpty ? user.username : user.fullName,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          forceMaterialTransparency: true,
          elevation: 0,
          actions: const [
            SizedBox(width: 8),
          ],
          flexibleSpace: const _AppBarGradientBg(),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.event), text: 'Events'),
              Tab(icon: Icon(Icons.fact_check), text: 'Attendance'),
            ],
          ),
        ),
        body: _TabBackground(
          child: TabBarView(
            children: [
              const FacultyEventsTab(),
              FacultyAttendanceTab(user: user),
            ],
          ),
        ),
      ),
    );
  }
}

class FacultyPendingApprovalScreen extends ConsumerWidget {
  const FacultyPendingApprovalScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      extendBody: false,
      appBar: AppBar(
        title: const Text('Faculty Verification'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        elevation: 0,
        flexibleSpace: const _AppBarGradientBg(),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_user_outlined, size: 56),
                  const SizedBox(height: 12),
                  const Text(
                    'Your faculty account is waiting for admin approval.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please contact your admin. You can login after verification.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      final msg = await ref.read(authProvider.notifier).refreshCurrentUser();
                      if (!context.mounted) return;
                      if (msg != null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(msg)),
                        );
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Approval confirmed. Welcome!')),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh Approval'),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => ref.read(authProvider.notifier).logout(),
                    icon: const Icon(Icons.logout),
                    label: const Text('Logout'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminEventsTab extends ConsumerStatefulWidget {
  const AdminEventsTab({super.key});

  @override
  ConsumerState<AdminEventsTab> createState() => _AdminEventsTabState();
}

class FacultyEventsTab extends ConsumerWidget {
  const FacultyEventsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(eventProvider);
    return eventsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (events) {
        final sorted = [...events]..sort((a, b) => b.date.compareTo(a.date));
        return RefreshIndicator(
          onRefresh: () => ref.read(eventProvider.notifier).loadEvents(),
          child: sorted.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'No events yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final event = sorted[index];
                    return Card(
                      child: ListTile(
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.event,
                            color: Theme.of(context).colorScheme.onSecondaryContainer,
                          ),
                        ),
                        title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            '${event.date.toLocal()}'.split(' ')[0],
                            event.status.toUpperCase(),
                            if (event.startAt != null && event.endAt != null)
                              '${TimeOfDay.fromDateTime(event.startAt!).format(context)}-${TimeOfDay.fromDateTime(event.endAt!).format(context)}',
                          ].join(' • '),
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _AdminEventsTabState extends ConsumerState<AdminEventsTab> {
  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventProvider);
    return eventsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (events) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Events',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.qr_code_2,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Tap any event to edit it. After editing, changes are instantly visible to students.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: events.isEmpty
                    ? Center(
                        child: Text(
                          'No events yet',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: events.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final event = events[index];
                          final scheme = Theme.of(context).colorScheme;
                          final courseCodes = event.courses.map((c) => kCourseShort[c] ?? c).toList();
                          final shownCodes = courseCodes.take(3).toList();
                          final remainingCourses = courseCodes.length - shownCodes.length;
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showEventDialog(context, ref, existing: event),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: ListTile(
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: scheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      event.isCategory ? Icons.layers : Icons.event,
                                      color: scheme.onSecondaryContainer,
                                    ),
                                  ),
                                  title: Text(event.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        [
                                          '${event.date.toLocal()}'.split(' ')[0],
                                          event.status.toUpperCase(),
                                          if (event.startAt != null && event.endAt != null)
                                            '${TimeOfDay.fromDateTime(event.startAt!).format(context)}-${TimeOfDay.fromDateTime(event.endAt!).format(context)}',
                                        ].join(' • '),
                                        style: const TextStyle(color: Colors.black54),
                                      ),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          if (event.isCategory)
                                            FilterChip(
                                              visualDensity: VisualDensity.compact,
                                              avatar: Icon(Icons.layers, size: 14, color: scheme.primary),
                                              label: const Text('Category', style: TextStyle(fontSize: 11)),
                                              onSelected: null,
                                            )
                                          else if (event.parentId != null)
                                            FilterChip(
                                              visualDensity: VisualDensity.compact,
                                              avatar: Icon(Icons.folder_outlined, size: 14, color: scheme.tertiary),
                                              label: const Text('Sub-event', style: TextStyle(fontSize: 11)),
                                              onSelected: null,
                                            ),
                                          if (event.allCourses)
                                            Chip(
                                              visualDensity: VisualDensity.compact,
                                              label: const Text('All Courses', style: TextStyle(fontSize: 11)),
                                              backgroundColor: Colors.green.shade100,
                                            )
                                          else ...[
                                            ...shownCodes.map((c) => Chip(
                                                  visualDensity: VisualDensity.compact,
                                                  label: Text(c, style: const TextStyle(fontSize: 11)),
                                                )),
                                            if (remainingCourses > 0)
                                              Chip(
                                                visualDensity: VisualDensity.compact,
                                                label: Text('+$remainingCourses more', style: const TextStyle(fontSize: 11)),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(event.status == 'open' ? Icons.lock_open : Icons.lock),
                                        onPressed: () async {
                                          final next = event.status == 'open' ? 'closed' : 'open';
                                          await ref.read(eventProvider.notifier).updateEvent(event.id, status: next, startAt: event.startAt, endAt: event.endAt);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.qr_code),
                                        onPressed: () => _showEventQr(context, event),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline),
                                        onPressed: () => ref.read(eventProvider.notifier).deleteEvent(event.id),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _showEventDialog(
  BuildContext context,
  WidgetRef ref, {
  Event? existing,
}) async {
  final isEdit = existing != null;
  final nameController = TextEditingController(text: existing?.name ?? '');
  final descriptionController = TextEditingController(text: existing?.description ?? '');
  DateTime date = existing?.date ?? DateTime.now();
  String status = existing?.status ?? 'open';
  bool enableWindow = (existing?.startAt != null) && (existing?.endAt != null);
  TimeOfDay startTime = existing?.startAt != null
      ? TimeOfDay.fromDateTime(existing!.startAt!)
      : const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = existing?.endAt != null
      ? TimeOfDay.fromDateTime(existing!.endAt!)
      : const TimeOfDay(hour: 17, minute: 0);
  Uint8List? pickedBytes;
  String posterDataUrl = existing?.posterImageUrl ?? '';
  bool busyPicking = false;
  bool allCourses = existing?.allCourses ?? true;
  Set<String> pickedCourses = allCourses
      ? <String>{}
      : (existing?.courses ?? <String>[]).toSet();
  final scrollController = ScrollController();
  final imagePicker = ImagePicker();
  if (posterDataUrl.trim().isNotEmpty && posterDataUrl.startsWith('data:')) {
    try {
      final comma = posterDataUrl.indexOf(',');
      if (comma != -1) {
        pickedBytes = base64Decode(posterDataUrl.substring(comma + 1));
      }
    } catch (_) {}
  }
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(isEdit ? 'Edit Event' : 'Add Event'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 720),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Event name',
                    prefixIcon: Icon(Icons.event_available),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 6,
                  minLines: 3,
                  maxLength: 5000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                    counterText: '',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 88),
                      child: Icon(Icons.notes),
                    ),
                    hintText: 'Write event details, required attire, etc. (max 5000 chars)',
                  ),
                ),
                const SizedBox(height: 12),
                if (pickedBytes != null) ...[
                  Stack(
                    children: [
                      Container(
                        width: double.infinity,
                        height: 180,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.memory(pickedBytes!, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            setState(() {
                              pickedBytes = null;
                              posterDataUrl = '';
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: busyPicking
                      ? null
                      : () async {
                          setState(() => busyPicking = true);
                          try {
                            final picked = await imagePicker.pickImage(
                              source: ImageSource.gallery,
                              maxWidth: _kPosterMaxSidePx.toDouble(),
                              maxHeight: _kPosterMaxSidePx.toDouble(),
                              imageQuality: 100,
                            );
                            if (picked != null) {
                              Uint8List bytes = await picked.readAsBytes();
                              try {
                                final preserved = await _compressPosterBytes(bytes);
                                if (preserved.isNotEmpty) bytes = preserved;
                              } catch (_) {
                                // keep original
                              }
                              if (bytes.lengthInBytes > _kPosterMaxBytes) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      duration: const Duration(seconds: 4),
                                      content: Text(
                                        'Poster image exceeds the 5 MB limit (yours is ${_formatBytes(bytes.lengthInBytes)}). Upload a smaller file.',
                                      ),
                                      backgroundColor: Colors.deepOrangeAccent,
                                    ),
                                  );
                                }
                                setState(() => busyPicking = false);
                                return;
                              }
                              final mime = picked.mimeType ??
                                  (picked.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
                              final b64 = base64Encode(bytes);
                              if (b64.length > _kPosterMaxBase64Chars) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      duration: const Duration(seconds: 4),
                                      content: Text(
                                        'Poster encoded size too large (${_formatBytes(b64.length)}). Upload a smaller file.',
                                      ),
                                      backgroundColor: Colors.deepOrangeAccent,
                                    ),
                                  );
                                }
                                setState(() => busyPicking = false);
                                return;
                              }
                              setState(() {
                                pickedBytes = bytes;
                                posterDataUrl = 'data:$mime;base64,$b64';
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    duration: const Duration(seconds: 2),
                                    content: Text(
                                      'Poster attached (${_formatBytes(bytes.lengthInBytes)}). Quality and dimensions preserved.',
                                    ),
                                    backgroundColor: Colors.green.shade700,
                                  ),
                                );
                              }
                            }
                          } finally {
                            if (context.mounted) {
                              setState(() => busyPicking = false);
                            }
                          }
                        },
                  icon: busyPicking
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.image_outlined),
                  label: Text(pickedBytes == null ? 'Attach poster image' : 'Change poster image'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: Text('${date.toLocal()}'.split(' ')[0])),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => date = picked);
                        }
                      },
                      child: const Text('Pick date'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('event_status_${existing?.id ?? 'new'}'),
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => status = value);
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable time window'),
                  value: enableWindow,
                  onChanged: (v) => setState(() => enableWindow = v),
                ),
                if (enableWindow) ...[
                  Row(
                    children: [
                      Expanded(child: Text('Start: ${startTime.format(context)}')),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: startTime);
                          if (picked != null) setState(() => startTime = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('End: ${endTime.format(context)}')),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(context: context, initialTime: endTime);
                          if (picked != null) setState(() => endTime = picked);
                        },
                        child: const Text('Pick'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('All Courses (visible to every student)'),
                  value: allCourses,
                  onChanged: (v) => setState(() => allCourses = v),
                ),
                if (!allCourses) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Select courses',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: kCoursesList.map((course) {
                      final short = kCourseShort[course] ?? course;
                      final isSelected = pickedCourses.contains(course);
                      return FilterChip(
                        label: Text(short),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              pickedCourses.add(course);
                            } else {
                              pickedCourses.remove(course);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: allCourses
                      ? [
                          Chip(
                            label: const Text('All Courses'),
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          ),
                        ]
                      : pickedCourses.map((course) {
                          final short = kCourseShort[course] ?? course;
                          return Chip(
                            label: Text(short),
                          );
                        }).toList(),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () {
            Navigator.pop(context);
            nameController.dispose();
            descriptionController.dispose();
          }, child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Event name is required')),
                    );
                  }
                  return;
                }
                if (!allCourses && pickedCourses.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Pick at least one course, or enable "All Courses".'),
                        backgroundColor: Colors.deepOrangeAccent,
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                  return;
                }
                final prefs = await SharedPreferences.getInstance();
                final token = prefs.getString('auth_token');
                if (token == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Offline mode: connect to the server and login again to create events.')),
                    );
                  }
                  return;
                }
                DateTime? startAt;
                DateTime? endAtDt;
                if (enableWindow) {
                  startAt = DateTime(date.year, date.month, date.day, startTime.hour, startTime.minute);
                  endAtDt = DateTime(date.year, date.month, date.day, endTime.hour, endTime.minute);
                }
                final notifier = ref.read(eventProvider.notifier);
                if (isEdit) {
                  final updated = await notifier.updateEvent(
                    existing.id,
                    name: name,
                    date: date,
                    status: status,
                    startAt: startAt,
                    endAt: endAtDt,
                    description: descriptionController.text.trim(),
                    posterImageUrl: posterDataUrl,
                    allCourses: allCourses,
                    courses: allCourses ? const [] : pickedCourses.toList(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (updated != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Event updated — changes now visible to students.'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                } else {
                  final created = await notifier.addEvent(
                    name,
                    date,
                    status: status,
                    startAt: startAt,
                    endAt: endAtDt,
                    description: descriptionController.text.trim(),
                    posterImageUrl: posterDataUrl,
                    allCourses: allCourses,
                    courses: allCourses ? const [] : pickedCourses.toList(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context);
                  if (created != null) {
                    await _showEventQr(context, created);
                  }
                }
              } finally {
                // Disposed on Cancel path above; no-op here to avoid double-dispose.
              }
            },
            child: Text(isEdit ? 'Save Changes' : 'Add'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showEventQr(BuildContext context, Event event) async {
  final data = jsonEncode({'eventId': event.id});
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Event QR: ${event.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(data: data, size: 220),
          ),
          const SizedBox(height: 12),
          SelectableText(data),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: data));
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Copy'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    ),
  );
}

class AdminAttendanceTab extends ConsumerWidget {
  const AdminAttendanceTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceState = ref.watch(attendanceProvider);
    return attendanceState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (attendance) {
        final sorted = [...attendance]..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return RefreshIndicator(
          onRefresh: () => ref.read(attendanceProvider.notifier).loadAttendance(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final r = sorted[index];
              final checkIn = r.checkInAt ?? r.timestamp;
              final expectedOut = checkIn.add(const Duration(minutes: attendanceTimeoutMinutes));
              final out = r.checkOutAt ?? expectedOut;
              final isOut = r.checkOutAt != null;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.how_to_reg,
                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                      ),
                    ),
                    title: Text(r.eventName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${r.studentName} (${r.studentId})\nIn: ${checkIn.toLocal()} • Out: ${out.toLocal()}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    trailing: _StatusChip(isOut: isOut),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class AdminReportsTab extends ConsumerStatefulWidget {
  const AdminReportsTab({super.key});

  @override
  ConsumerState<AdminReportsTab> createState() => _AdminReportsTabState();
}

class _AdminReportsTabState extends ConsumerState<AdminReportsTab> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final attendanceState = ref.watch(attendanceProvider);
    final currentUser = ref.watch(authProvider).value;
    final isAdmin = currentUser != null && currentUser.role == 'admin';

    return attendanceState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (attendance) {
        final mine = currentUser == null
            ? attendance
            : attendance
                .where((r) =>
                    r.userId == currentUser.id ||
                    r.studentId == currentUser.username ||
                    (currentUser.studentId.isNotEmpty && r.studentId == currentUser.studentId))
                .toList();

        final visible = (isAdmin && _showAll) ? attendance : mine;

        final sorted = [...visible]..sort((a, b) {
          final aIn = a.checkInAt ?? a.timestamp;
          final bIn = b.checkInAt ?? b.timestamp;
          return bIn.compareTo(aIn);
        });

        final csv = _toCsv(sorted);
        final totalRows = sorted.length;

        final deleteLabel = (isAdmin && _showAll) ? 'Delete all attendance' : 'Delete my attendance';
        final deleteTitle = (isAdmin && _showAll) ? 'Delete all attendance?' : 'Delete your attendance?';
        final deleteBody = (isAdmin && _showAll)
            ? 'This will remove all attendance records from the server.'
            : 'This will remove your attendance records from the server.';

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Reports',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (isAdmin)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('All'),
                        Switch(
                          value: _showAll,
                          onChanged: (v) => setState(() => _showAll = v),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard(title: 'Rows', value: '$totalRows'),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Export (Name + Course + Section + In/Out)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      FilledButton(
                        onPressed: () async => Clipboard.setData(ClipboardData(text: csv)),
                        child: const Text('Copy'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          deleteLabel,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFB3261E),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: totalRows == 0
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(deleteTitle),
                                    content: Text(deleteBody),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFFB3261E),
                                          foregroundColor: Colors.white,
                                        ),
                                        onPressed: () => Navigator.pop(context, true),
                                        child: const Text('Delete'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                if (isAdmin && _showAll) {
                                  await ApiService.clearAttendance();
                                } else {
                                  await ApiService.deleteMyAttendance();
                                }
                                ref.read(attendanceProvider.notifier).loadAttendance();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Attendance cleared')),
                                  );
                                }
                              },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (sorted.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'No attendance yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                    ),
                  ),
                )
              else
                ...sorted.map((r) {
                  final checkIn = r.checkInAt ?? r.timestamp;
                  final checkOut = r.checkOutAt;
                  final course = r.studentCourse.trim().isEmpty ? 'N/A' : r.studentCourse.trim();
                  final section = r.studentSection.trim().isEmpty ? 'N/A' : r.studentSection.trim();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                            child: Text(r.studentName.isEmpty ? '?' : r.studentName[0].toUpperCase()),
                          ),
                          title: Text(r.studentName, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            'Course: $course • Section: $section\n'
                            'In: ${checkIn.toLocal()}\n'
                            'Out: ${(checkOut ?? checkIn.add(const Duration(minutes: attendanceTimeoutMinutes))).toLocal()}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: isAdmin && _showAll
                                ? () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Delete record?'),
                                        content: Text('Delete attendance for ${r.studentName}?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                          FilledButton(
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xFFB3261E),
                                              foregroundColor: Colors.white,
                                            ),
                                            onPressed: () => Navigator.pop(context, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await ApiService.deleteAttendanceRecord(r.id);
                                    ref.read(attendanceProvider.notifier).loadAttendance();
                                  }
                                : null,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  String _toCsv(List<AttendanceRecord> attendance) {
    final buffer = StringBuffer();
    buffer.writeln('studentName,studentCourse,studentSection,checkInAt,checkOutAt');
    for (final r in attendance) {
      final checkIn = r.checkInAt ?? r.timestamp;
      buffer.writeln([
        _csvCell(r.studentName),
        _csvCell(r.studentCourse),
        _csvCell(r.studentSection),
        _csvCell(checkIn.toIso8601String()),
        _csvCell(r.checkOutAt?.toIso8601String() ?? ''),
      ].join(','));
    }
    return buffer.toString();
  }

  String _csvCell(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AdminUsersTab extends ConsumerStatefulWidget {
  const AdminUsersTab({super.key});

  @override
  ConsumerState<AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends ConsumerState<AdminUsersTab> {
  late Future<List<User>> _future;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _future = _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<User>> _loadUsers() async {
    final list = await ApiService.getUsers();
    return list.map((u) => User.fromJson(u)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Users',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _showAddUserDialog(context),
                icon: const Icon(Icons.person_add),
                label: const Text('Add User'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _future = _loadUsers()),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search by user ID, username, or student ID',
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<User>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Failed to load users',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            snapshot.error.toString(),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => setState(() => _future = _loadUsers()),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final users = snapshot.data!;
                final filteredUsers = _searchQuery.isEmpty
                    ? users
                    : users.where((u) {
                        final id = u.id.toLowerCase();
                        final username = u.username.toLowerCase();
                        final studentId = u.studentId.toLowerCase();
                        final fullName = u.fullName.toLowerCase();
                        return id.contains(_searchQuery) ||
                            username.contains(_searchQuery) ||
                            studentId.contains(_searchQuery) ||
                            fullName.contains(_searchQuery);
                      }).toList();
                if (filteredUsers.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No users yet' : 'No users found',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                    ),
                  );
                }
                final students = filteredUsers.where((u) => u.role == 'student').toList()
                  ..sort((a, b) => '${a.course}|${a.section}|${a.fullName}|${a.username}'.compareTo(
                        '${b.course}|${b.section}|${b.fullName}|${b.username}',
                      ));
                final others = filteredUsers.where((u) => u.role != 'student').toList()
                  ..sort((a, b) => '${a.role}|${a.fullName}|${a.username}'.compareTo('${b.role}|${b.fullName}|${b.username}'));
                final groups = <String, List<User>>{};
                for (final s in students) {
                  final key = '${s.course.isEmpty ? 'Unknown course' : s.course} • ${s.section.isEmpty ? 'Unknown section' : s.section}';
                  (groups[key] ??= []).add(s);
                }

                final tiles = <Widget>[];
                for (final entry in groups.entries) {
                  tiles.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                      child: Text(
                        entry.key,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  );
                  for (final u in entry.value) {
                    final canEditUserId = currentUser == null || u.id != currentUser.id;
                    final canDelete = currentUser != null && u.id != currentUser.id;
                    tiles.add(
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                              child: Text(u.username.isEmpty ? '?' : u.username[0].toUpperCase()),
                            ),
                            title: Text(u.fullName.isEmpty ? u.username : u.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${u.studentId.isEmpty ? u.username : u.studentId} • ${u.username}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'User actions',
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  _showEditUserDialog(
                                    context,
                                    u,
                                    canEditUserId: canEditUserId,
                                  );
                                  return;
                                }
                                if (value == 'reset') {
                                  _showAdminResetPasswordDialog(context, u);
                                  return;
                                }
                                if (value == 'delete' && canDelete) {
                                  await ApiService.deleteUser(u.id);
                                  if (!mounted) return;
                                  setState(() => _future = _loadUsers());
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('Edit user'),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'reset',
                                  child: Text('Reset password'),
                                ),
                                if (canDelete)
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('Delete user'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                }

                if (others.isNotEmpty) {
                  tiles.add(
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text(
                        'Staff Accounts',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  );
                  for (final u in others) {
                    final canEditUserId = currentUser == null || u.id != currentUser.id;
                    final canDelete = currentUser != null && u.id != currentUser.id;
                    tiles.add(
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                              child: Text(u.role.isEmpty ? '?' : u.role[0].toUpperCase()),
                            ),
                            title: Text(u.fullName.isEmpty ? u.username : u.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              '${u.role.toUpperCase()} • ${u.username}${u.role == 'faculty' && !u.isApproved ? ' • Pending approval' : ''}',
                              style: const TextStyle(color: Colors.black54),
                            ),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'User actions',
                              onSelected: (value) async {
                                if (value == 'approve') {
                                  try {
                                    await ApiService.updateUser(u.id, isApproved: true);
                                    if (!mounted || !context.mounted) return;
                                    setState(() => _future = _loadUsers());
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('${u.username} verified')),
                                    );
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                  return;
                                }
                                if (value == 'edit') {
                                  _showEditUserDialog(
                                    context,
                                    u,
                                    canEditUserId: canEditUserId,
                                  );
                                  return;
                                }
                                if (value == 'reset') {
                                  _showAdminResetPasswordDialog(context, u);
                                  return;
                                }
                                if (value == 'delete' && canDelete) {
                                  await ApiService.deleteUser(u.id);
                                  if (!mounted) return;
                                  setState(() => _future = _loadUsers());
                                }
                              },
                              itemBuilder: (_) => [
                                if (u.role == 'faculty' && !u.isApproved)
                                  const PopupMenuItem<String>(
                                    value: 'approve',
                                    child: Text('Approve faculty'),
                                  ),
                                const PopupMenuItem<String>(
                                  value: 'edit',
                                  child: Text('Edit user'),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'reset',
                                  child: Text('Reset password'),
                                ),
                                if (canDelete)
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: Text('Delete user'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: tiles,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddUserDialog(BuildContext context) async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
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
    String role = 'student';

    List<String> buildSections() {
      if (selectedCourse == null || selectedYear == null) return const [];
      final code = courseCodes[selectedCourse] ?? 'BS';
      return List<String>.generate(
        26,
        (i) => '$code $selectedYear${String.fromCharCode(65 + i)}',
      );
    }

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Add User'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
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
                  onChanged: (v) => setStateDialog(() {
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
                  onChanged: (v) => setStateDialog(() {
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
                  onChanged: (v) => setStateDialog(() => selectedSection = v),
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
                  setStateDialog(() {
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
                try {
                  await ApiService.createUser(
                    username,
                    password,
                    role,
                    fullName: fullName.isEmpty ? null : fullName,
                    studentId: role == 'student' ? studentId : null,
                    course: role == 'student' ? selectedCourse : null,
                    section: role == 'student' ? selectedSection : null,
                  );
                  if (!mounted || !context.mounted) return;
                  setState(() => _future = _loadUsers());
                  Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User added')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAdminResetPasswordDialog(BuildContext context, User user) async {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureNew = true;
    bool obscureConfirm = true;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Reset Password - ${user.username}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                final newPassword = newPasswordController.text;
                final confirmPassword = confirmPasswordController.text;
                if (newPassword.isEmpty || confirmPassword.isEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields')),
                  );
                  return;
                }
                if (newPassword != confirmPassword) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password confirmation does not match')),
                  );
                  return;
                }
                if (newPassword.length < 6) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Password must be at least 6 characters')),
                  );
                  return;
                }
                try {
                  await ApiService.adminResetUserPassword(user.id, newPassword);
                  if (!context.mounted) return;
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Password reset for ${user.username}')),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _showEditUserDialog(
    BuildContext context,
    User user, {
    required bool canEditUserId,
  }) async {
    final userIdController = TextEditingController(text: user.id);
    final usernameController = TextEditingController(text: user.username);
    final passwordController = TextEditingController();
    final fullNameController = TextEditingController(text: user.fullName);
    final studentIdController = TextEditingController(text: user.studentId);
    final courseController = TextEditingController(text: user.course);
    final sectionController = TextEditingController(text: user.section);
    String role = user.role;
    bool obscurePassword = true;
    bool isApproved = user.isApproved;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text('Edit User - ${user.username}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: userIdController,
                  enabled: canEditUserId,
                  decoration: InputDecoration(
                    labelText: 'User ID',
                    helperText: canEditUserId ? null : 'You cannot edit your own User ID',
                  ),
                ),
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'New Password (optional)',
                    suffixIcon: IconButton(
                      tooltip: obscurePassword ? 'Show password' : 'Hide password',
                      onPressed: () => setStateDialog(() => obscurePassword = !obscurePassword),
                      icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                    ),
                  ),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey('edit_role_${user.id}'),
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'student', child: Text('Student')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'faculty', child: Text('Faculty')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setStateDialog(() {
                      role = value;
                      if (role != 'faculty') isApproved = true;
                    });
                  },
                ),
                TextField(
                  controller: fullNameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                ),
                TextField(
                  controller: studentIdController,
                  decoration: const InputDecoration(labelText: 'Student ID'),
                ),
                TextField(
                  controller: courseController,
                  decoration: const InputDecoration(labelText: 'Course'),
                ),
                TextField(
                  controller: sectionController,
                  decoration: const InputDecoration(labelText: 'Section'),
                ),
                if (role == 'faculty') ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Account approved (can sign in)'),
                    subtitle: isApproved
                        ? const Text('Faculty can log in immediately after saving.')
                        : const Text('A pending approval error will appear on login.'),
                    value: isApproved,
                    onChanged: (v) => setStateDialog(() => isApproved = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final nextId = userIdController.text.trim();
                final nextUsername = usernameController.text.trim();
                final nextPassword = passwordController.text;
                final nextFullName = fullNameController.text.trim();
                final nextStudentId = studentIdController.text.trim();
                final nextCourse = courseController.text.trim();
                final nextSection = sectionController.text.trim();

                if (nextId.isEmpty || nextUsername.isEmpty) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User ID and username are required')),
                  );
                  return;
                }
                if (role == 'student' &&
                    (nextFullName.isEmpty ||
                        nextStudentId.isEmpty ||
                        nextCourse.isEmpty ||
                        nextSection.isEmpty)) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Student must have full name, student ID, course, and section')),
                  );
                  return;
                }
                if (nextPassword.isNotEmpty && nextPassword.length < 6) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('New password must be at least 6 characters')),
                  );
                  return;
                }

                try {
                  await ApiService.updateUser(
                    user.id,
                    id: nextId,
                    username: nextUsername,
                    password: nextPassword.isEmpty ? null : nextPassword,
                    role: role,
                    fullName: nextFullName,
                    studentId: nextStudentId,
                    course: nextCourse,
                    section: nextSection,
                    isApproved: role == 'faculty' ? isApproved : true,
                  );
                  if (!context.mounted) return;
                  Navigator.pop(dialogContext);
                  setState(() => _future = _loadUsers());
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        role == 'faculty'
                            ? isApproved
                                ? 'User updated and approved — faculty can now sign in.'
                                : 'User updated — account pending approval.'
                            : 'User updated',
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class StudentScannerTab extends ConsumerStatefulWidget {
  const StudentScannerTab({super.key, required this.user});

  final User user;

  @override
  ConsumerState<StudentScannerTab> createState() => _StudentScannerTabState();
}

class _StudentScannerTabState extends ConsumerState<StudentScannerTab> {
  late final MobileScannerController _scannerController;
  bool _processing = false;
  String _message = 'Scan a QR code to mark attendance.';
  int _lastRefreshMs = 0;
  bool _pickingFaculty = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventsState = ref.watch(eventProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      _processing ? Icons.sync : Icons.qr_code_scanner,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _message,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    onPressed: _processing
                        ? null
                        : () async {
                            setState(() {
                              _message = 'Refreshing events...';
                              _processing = true;
                            });
                            try {
                              await ref.read(eventProvider.notifier).loadEvents();
                              if (mounted) {
                                setState(() {
                                  _message = 'Scan a QR code to mark attendance.';
                                });
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() {
                                  _message = 'Refresh failed: $e';
                                });
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _processing = false);
                              }
                            }
                          },
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: eventsState.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (events) => ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    border: Border.all(color: const Color(0xFFE6E8F0)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, error, _) => Container(
                          color: const Color(0xFF0F172A),
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.no_photography_outlined, size: 56, color: Colors.white70),
                                const SizedBox(height: 12),
                                const Text(
                                  'Camera unavailable',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _friendlyMobileError(error),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                                const SizedBox(height: 14),
                                ElevatedButton.icon(
                                  onPressed: () => _scannerController.start(),
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Try again'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        placeholderBuilder: (ctx, _) => Container(
                          color: const Color(0xFF0F172A),
                          child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                        ),
                        onDetect: (capture) => _onDetect(capture, events),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ScanFramePainter(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture, List<Event> events) async {
    if (_processing) return;
    final barcode = capture.barcodes.isEmpty ? null : capture.barcodes.first;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() {
      _processing = true;
      _message = 'Processing...';
    });

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw Exception('Invalid QR data');
      }
      final eventId = decoded['eventId']?.toString();
      if (eventId == null) {
        throw Exception('Invalid QR data');
      }

      Event? event = events.where((e) => e.id == eventId).cast<Event?>().firstWhere((e) => e != null, orElse: () => null);
      if (event == null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastRefreshMs > 3000) {
          _lastRefreshMs = nowMs;
          await ref.read(eventProvider.notifier).loadEvents();
          final refreshed = ref.read(eventProvider).value;
          if (refreshed != null) {
            event = refreshed.where((e) => e.id == eventId).cast<Event?>().firstWhere((e) => e != null, orElse: () => null);
          }
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() {
          _message = 'Offline mode: connect to the server and login again to scan this QR.';
        });
        return;
      }

      final eventName = event?.name.isNotEmpty == true ? event!.name : 'Event';
      final studentId = widget.user.studentId.isNotEmpty ? widget.user.studentId : widget.user.username;
      final studentName = widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.username;

      if (_pickingFaculty) return;
      _pickingFaculty = true;
      if (!mounted) return;
      final pickedFacultyId = await _pickFacultyForThisScan(context, eventId, studentId);
      _pickingFaculty = false;
      if (pickedFacultyId == null) {
        setState(() {
          _message = 'Select a faculty to continue.';
        });
        return;
      }

      final msg = await ref.read(attendanceProvider.notifier).markAttendance(
            eventId,
            eventName,
            studentId,
            studentName,
            widget.user.id,
            facultyId: pickedFacultyId,
          );

      setState(() {
        _message = msg;
      });
    } catch (e) {
      setState(() {
        _message = 'Scan error: $e';
      });
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _processing = false;
        });
      }
    }
  }

  Future<String?> _pickFacultyForThisScan(BuildContext context, String eventId, String studentId) async {
    final attendanceNotifier = ref.read(attendanceProvider.notifier);
    // Always reload before deciding stage so second scan reliably shows Check-out.
    await attendanceNotifier.loadAttendance();
    final list = ref.read(attendanceProvider).value ?? const <AttendanceRecord>[];
    final now = DateTime.now();
    final open = list.where((r) {
      if (r.eventId != eventId) return false;
      if (r.studentId != studentId) return false;
      if (r.checkOutAt != null) return false;
      final checkIn = r.checkInAt ?? r.timestamp;
      return checkIn.year == now.year && checkIn.month == now.month && checkIn.day == now.day;
    }).cast<AttendanceRecord?>().firstWhere((r) => r != null, orElse: () => null);
    final stage = open == null ? 'Check-in' : 'Check-out';

    final rawFaculty = await ApiService.getFaculty();
    final faculty = rawFaculty.map((u) => User.fromJson(u)).toList();
    if (faculty.isEmpty) {
      if (mounted) {
        setState(() {
          _message = 'No faculty accounts found. Ask admin to create faculty accounts.';
        });
      }
      return null;
    }

    String selectedId = faculty.first.id;
    if (!context.mounted) return null;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Choose faculty for $stage'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedId,
            items: faculty
                .map(
                  (f) => DropdownMenuItem(
                    value: f.id,
                    child: Text(f.fullName.isEmpty ? f.username : f.fullName),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => selectedId = v);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, selectedId), child: const Text('Continue')),
          ],
        ),
      ),
    );
    return picked;
  }
}

class StudentAttendanceTab extends ConsumerWidget {
  const StudentAttendanceTab({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attendanceState = ref.watch(attendanceProvider);
    return attendanceState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (attendance) {
        final mine = attendance
            .where((r) =>
                r.userId == user.id ||
                r.studentId == user.username ||
                (user.studentId.isNotEmpty && r.studentId == user.studentId))
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return RefreshIndicator(
          onRefresh: () => ref.read(attendanceProvider.notifier).loadAttendance(),
          child: mine.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'No attendance yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: mine.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final r = mine[index];
                    final checkIn = r.checkInAt ?? r.timestamp;
                    final expectedOut = checkIn.add(const Duration(minutes: attendanceTimeoutMinutes));
                    final out = r.checkOutAt ?? expectedOut;
                    final isOut = r.checkOutAt != null;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.event_available,
                              color: Theme.of(context).colorScheme.onSecondaryContainer,
                            ),
                          ),
                          title: Text(r.eventName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            'In: ${checkIn.toLocal()}\nOut: ${out.toLocal()}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          trailing: _StatusChip(isOut: isOut),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class StudentEventsTab extends ConsumerWidget {
  const StudentEventsTab({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsState = ref.watch(eventProvider);
    return eventsState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (events) {
        final rootEvents = events.where((e) => e.status != 'draft' && e.parentId == null).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final categories = rootEvents.where((e) => e.isCategory).toList();
        final regular = rootEvents.where((e) => !e.isCategory).toList();
        return RefreshIndicator(
          onRefresh: () => ref.read(eventProvider.notifier).loadEvents(),
          child: categories.isEmpty && regular.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const SizedBox(height: 40),
                    Center(
                      child: Text(
                        'No published events yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                      ),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (categories.isNotEmpty) ...[
                      Text(
                        'Event Categories',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      ...categories.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _EventListTile(
                              event: e,
                              onTap: () {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => _CategoryMenuScreen(category: e, user: user),
                                  ),
                                );
                              },
                            ),
                          )),
                      const SizedBox(height: 4),
                    ],
                    if (regular.isNotEmpty) ...[
                      Text(
                        'Events',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      ...regular.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _EventListTile(
                              event: e,
                              onTap: () {
                                Navigator.of(context).push<void>(
                                  MaterialPageRoute(
                                    builder: (_) => _EventDetailScreen(event: e, user: user),
                                  ),
                                );
                              },
                            ),
                          )),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _CategoryMenuScreen extends ConsumerWidget {
  final Event category;
  final User user;
  const _CategoryMenuScreen({required this.category, required this.user});

  Uint8List? _decodePoster() {
    final url = category.posterImageUrl;
    if (url.isEmpty) return null;
    final prefix = ';base64,';
    final idx = url.indexOf(prefix);
    if (idx < 0) return null;
    try {
      return base64Decode(url.substring(idx + prefix.length));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posterBytes = _decodePoster();
    final textTheme = Theme.of(context).textTheme;
    final eventsState = ref.watch(eventProvider);
    final subEvents = eventsState.valueOrNull
            ?.where((e) => e.parentId == category.id && e.status != 'draft')
            .toList()
      ?..sort((a, b) => b.date.compareTo(a.date));
    return Scaffold(
      appBar: AppBar(
        title: Text(category.name),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        elevation: 0,
        flexibleSpace: const _AppBarGradientBg(),
      ),
      body: _TabBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (posterBytes != null) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                child: Image.memory(posterBytes, fit: BoxFit.cover, height: 180, width: double.infinity),
              ),
              const SizedBox(height: 14),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        '${category.date.toLocal()}'.split(' ')[0],
                        category.status.toUpperCase(),
                        if (category.startAt != null && category.endAt != null)
                          '${TimeOfDay.fromDateTime(category.startAt!).format(context)}-${TimeOfDay.fromDateTime(category.endAt!).format(context)}',
                      ].join(' • '),
                      style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (category.allCourses)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('All Courses', style: TextStyle(fontSize: 12)),
                            backgroundColor: Colors.green.shade100,
                          )
                        else
                          ..._buildCourseChips(category.courses),
                      ],
                    ),
                    if (category.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          category.description.trim(),
                          style: textTheme.bodyMedium?.copyWith(height: 1.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Activities',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (subEvents == null)
              const Center(child: CircularProgressIndicator())
            else if (subEvents.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No activities yet in this category.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                  ),
                ),
              )
            else
              ...subEvents.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _EventListTile(
                      event: e,
                      onTap: () {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => _EventDetailScreen(event: e, user: user),
                          ),
                        );
                      },
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCourseChips(List<String> courses) {
    final chips = <Widget>[];
    final codes = courses.map((c) => kCourseShort[c] ?? c).toList();
    final shown = codes.take(3).toList();
    final remaining = codes.length - shown.length;
    for (final c in shown) {
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        label: Text(c, style: const TextStyle(fontSize: 12)),
      ));
    }
    if (remaining > 0) {
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        label: Text('+$remaining more', style: const TextStyle(fontSize: 12)),
      ));
    }
    return chips;
  }
}

class _EventListTile extends StatelessWidget {
  const _EventListTile({required this.event, required this.onTap});
  final Event event;
  final VoidCallback onTap;

  Uint8List? _decodePoster() {
    final url = event.posterImageUrl;
    if (url.isEmpty) return null;
    final prefix = ';base64,';
    final idx = url.indexOf(prefix);
    if (idx < 0) return null;
    try {
      return base64Decode(url.substring(idx + prefix.length));
    } catch (_) {
      return null;
    }
  }

  List<Widget> _buildCourseChips(List<String> courses, BuildContext context) {
    final chips = <Widget>[];
    final codes = courses.map((c) => kCourseShort[c] ?? c).toList();
    final shown = codes.take(3).toList();
    final remaining = codes.length - shown.length;
    for (final c in shown) {
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        label: Text(c, style: const TextStyle(fontSize: 11)),
      ));
    }
    if (remaining > 0) {
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        label: Text('+$remaining more', style: const TextStyle(fontSize: 11)),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final posterBytes = _decodePoster();
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 88,
                  height: 88,
                  color: scheme.secondaryContainer.withValues(alpha: 0.5),
                  child: posterBytes != null
                      ? Image.memory(posterBytes, fit: BoxFit.cover)
                      : Icon(Icons.event_rounded,
                          size: 38, color: scheme.onSecondaryContainer),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      event.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${event.date.toLocal()}'.split(' ')[0],
                        event.status.toUpperCase(),
                        if (event.startAt != null && event.endAt != null)
                          '${TimeOfDay.fromDateTime(event.startAt!).format(context)}-${TimeOfDay.fromDateTime(event.endAt!).format(context)}',
                      ].join(' • '),
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (event.isCategory)
                          FilterChip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(Icons.layers, size: 14, color: scheme.primary),
                            label: const Text('Category', style: TextStyle(fontSize: 11)),
                            onSelected: null,
                          )
                        else if (event.parentId != null)
                          FilterChip(
                            visualDensity: VisualDensity.compact,
                            avatar: Icon(Icons.folder_outlined, size: 14, color: scheme.tertiary),
                            label: const Text('Sub-event', style: TextStyle(fontSize: 11)),
                            onSelected: null,
                          ),
                        if (event.allCourses)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: const Text('All Courses', style: TextStyle(fontSize: 11)),
                            backgroundColor: Colors.green.shade100,
                          )
                        else
                          ..._buildCourseChips(event.courses, context),
                      ],
                    ),
                    if (event.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        event.description.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

String _friendlyMobileError(Object? error) {
  final s = error?.toString() ?? '';
  if (s.contains('permission') || s.contains('Permission')) {
    return 'Camera permission is required. Please enable camera access for this app in your phone settings, then try again.';
  }
  if (s.contains('already') || s.contains('active')) {
    return 'The camera is already in use. Please close any other camera apps and tap "Try again".';
  }
  if (s.contains('not found') || s.contains('unavailable') || s.toLowerCase().contains('no camera')) {
    return 'No back camera was detected on this device.';
  }
  return s.isEmpty
      ? 'The camera could not be started. Please restart the app and allow camera permission when asked.'
      : s;
}

class _ScanFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const inset = 48.0;
    const cornerLen = 36.0;
    const stroke = 4.0;
    final rect = Rect.fromLTWH(inset, inset + 8, size.width - inset * 2, size.height - inset * 2 - 16);
    final framePaint = Paint()
      ..color = const Color(0xFF3b82f6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final window = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16)));
    final dim = Path.combine(PathOperation.difference, outer, window);
    canvas.drawPath(dim, dimPaint);
    // Top-left
    final tl = rect.topLeft;
    canvas.drawLine(tl, tl.translate(cornerLen, 0), framePaint);
    canvas.drawLine(tl, tl.translate(0, cornerLen), framePaint);
    // Top-right
    final tr = rect.topRight;
    canvas.drawLine(tr, tr.translate(-cornerLen, 0), framePaint);
    canvas.drawLine(tr, tr.translate(0, cornerLen), framePaint);
    // Bottom-left
    final bl = rect.bottomLeft;
    canvas.drawLine(bl, bl.translate(cornerLen, 0), framePaint);
    canvas.drawLine(bl, bl.translate(0, -cornerLen), framePaint);
    // Bottom-right
    final br = rect.bottomRight;
    canvas.drawLine(br, br.translate(-cornerLen, 0), framePaint);
    canvas.drawLine(br, br.translate(0, -cornerLen), framePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EventDetailScreen extends ConsumerStatefulWidget {
  const _EventDetailScreen({required this.event, required this.user});
  final Event event;
  final User user;

  @override
  ConsumerState<_EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<_EventDetailScreen> {
  bool _showScanner = false;
  bool _processing = false;
  String _scanMessage = 'Scan the event QR to record your attendance.';
  bool _pickingFaculty = false;
  int _lastRefreshMs = 0;
  MobileScannerController? _detailScannerController;

  @override
  void dispose() {
    _detailScannerController?.dispose();
    super.dispose();
  }

  Uint8List? _decodePoster() {
    final url = widget.event.posterImageUrl;
    if (url.isEmpty) return null;
    final prefix = ';base64,';
    final idx = url.indexOf(prefix);
    if (idx < 0) return null;
    try {
      return base64Decode(url.substring(idx + prefix.length));
    } catch (_) {
      return null;
    }
  }

  ImageProvider? _posterImage() {
    final url = widget.event.posterImageUrl;
    if (url.isEmpty) return null;
    if (url.startsWith('data:')) {
      final bytes = _decodePoster();
      if (bytes == null) return null;
      return MemoryImage(bytes);
    }
    return NetworkImage(url);
  }

  List<Widget> _buildDetailCourseChips(List<String> courses) {
    final chips = <Widget>[];
    final codes = courses.map((c) => kCourseShort[c] ?? c).toList();
    final shown = codes.take(3).toList();
    final remaining = codes.length - shown.length;
    for (final c in shown) {
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        label: Text(c, style: const TextStyle(fontSize: 12)),
      ));
    }
    if (remaining > 0) {
      chips.add(Chip(
        visualDensity: VisualDensity.compact,
        label: Text('+$remaining more', style: const TextStyle(fontSize: 12)),
      ));
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final poster = _posterImage();
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.event.name),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        elevation: 0,
        flexibleSpace: const _AppBarGradientBg(),
      ),
      body: _TabBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (poster != null)
                    Ink.image(
                      image: poster,
                      fit: BoxFit.cover,
                      height: 220,
                      width: double.infinity,
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: 160,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.event_rounded,
                              size: 56, color: Theme.of(context).colorScheme.onPrimaryContainer),
                          const SizedBox(height: 6),
                          Text(
                            'No poster uploaded',
                            style: textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.event.name,
                          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            '${widget.event.date.toLocal()}'.split(' ')[0],
                            widget.event.status.toUpperCase(),
                            if (widget.event.startAt != null && widget.event.endAt != null)
                              '${TimeOfDay.fromDateTime(widget.event.startAt!).format(context)}-${TimeOfDay.fromDateTime(widget.event.endAt!).format(context)}',
                          ].join(' • '),
                          style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (widget.event.allCourses)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                label: const Text('All Courses', style: TextStyle(fontSize: 12)),
                                backgroundColor: Colors.green.shade100,
                              )
                            else
                              ..._buildDetailCourseChips(widget.event.courses),
                          ],
                        ),
                        if (widget.event.parentId != null) ...[
                          const SizedBox(height: 8),
                          Consumer(
                            builder: (context, cRef, _) {
                              final eventsState = cRef.watch(eventProvider);
                              final events = eventsState.valueOrNull ?? <Event>[];
                              final parent = events.cast<Event?>().firstWhere(
                                    (e) => e?.id == widget.event.parentId,
                                    orElse: () => null,
                                  );
                              if (parent == null) return const SizedBox.shrink();
                              return TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => _CategoryMenuScreen(category: parent, user: widget.user),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.folder_outlined),
                                label: Text('Open category: ${parent.name}'),
                              );
                            },
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (widget.event.description.trim().isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FC),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              'No description yet.',
                              style: textTheme.bodyMedium?.copyWith(color: Colors.black54),
                            ),
                          )
                        else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F8FC),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              widget.event.description.trim(),
                              style: textTheme.bodyMedium?.copyWith(height: 1.4),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.qr_code_2_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Scan QR for Attendance',
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _showScanner ? Icons.sync : Icons.qr_code_scanner,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _scanMessage,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          onPressed: _showScanner
                              ? null
                              : () async {
                                  setState(() {
                                    _scanMessage = 'Refreshing events...';
                                    _processing = true;
                                  });
                                  try {
                                    await ref.read(eventProvider.notifier).loadEvents();
                                    if (mounted) {
                                      setState(() {
                                        _scanMessage = 'Scan the event QR to record your attendance.';
                                      });
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      setState(() {
                                        _scanMessage = 'Refresh failed: $e';
                                      });
                                    }
                                  } finally {
                                    if (mounted) setState(() => _processing = false);
                                  }
                                },
                          icon: const Icon(Icons.refresh),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_showScanner)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => setState(() => _showScanner = true),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Open Scanner'),
                        ),
                      )
                    else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            border: Border.all(color: const Color(0xFFE6E8F0)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: SizedBox(
                            height: 300,
                            width: double.infinity,
                            child: Consumer(
                              builder: (context, cRef, _) {
                                final eventsState = cRef.watch(eventProvider);
                                final all = eventsState.valueOrNull ?? <Event>[];
                                _detailScannerController ??= MobileScannerController(
                                  detectionSpeed: DetectionSpeed.noDuplicates,
                                  autoStart: true,
                                );
                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    MobileScanner(
                                      controller: _detailScannerController!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (ctx, error, _) => Container(
                                        color: const Color(0xFF0F172A),
                                        padding: const EdgeInsets.all(14),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.no_photography_outlined, size: 44, color: Colors.white70),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Camera unavailable',
                                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                              ),
                                              const SizedBox(height: 6),
                                              Text(
                                                _friendlyMobileError(error),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                                              ),
                                              const SizedBox(height: 10),
                                              ElevatedButton.icon(
                                                onPressed: () => _detailScannerController?.start(),
                                                icon: const Icon(Icons.refresh),
                                                label: const Text('Retry'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      placeholderBuilder: (ctx, _) => Container(
                                        color: const Color(0xFF0F172A),
                                        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                                      ),
                                      onDetect: (capture) => _onDetect(capture, all),
                                    ),
                                    Positioned.fill(
                                      child: CustomPaint(painter: _ScanFramePainter()),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await _detailScannerController?.stop();
                            } catch (_) {}
                            _detailScannerController?.dispose();
                            if (!mounted) return;
                            setState(() {
                              _showScanner = false;
                              _detailScannerController = null;
                              _scanMessage = 'Scan the event QR to record your attendance.';
                            });
                          },
                          icon: const Icon(Icons.close),
                          label: const Text('Close Scanner'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDetect(BarcodeCapture capture, List<Event> events) async {
    if (_processing) return;
    final barcode = capture.barcodes.isEmpty ? null : capture.barcodes.first;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() {
      _processing = true;
      _scanMessage = 'Processing...';
    });

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw Exception('Invalid QR data');
      final eventId = decoded['eventId']?.toString();
      if (eventId == null) throw Exception('Invalid QR data');

      Event? event = events.where((e) => e.id == eventId).cast<Event?>().firstWhere((e) => e != null, orElse: () => null);
      if (event == null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (nowMs - _lastRefreshMs > 3000) {
          _lastRefreshMs = nowMs;
          await ref.read(eventProvider.notifier).loadEvents();
          final refreshed = ref.read(eventProvider).value;
          if (refreshed != null) {
            event = refreshed.where((e) => e.id == eventId).cast<Event?>().firstWhere((e) => e != null, orElse: () => null);
          }
        }
      }

      if (eventId != widget.event.id) {
        setState(() {
          _scanMessage = 'QR does not match this event. Scan the QR for: ${widget.event.name}';
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        setState(() {
          _scanMessage = 'Offline mode: connect to the server and login again to scan this QR.';
        });
        return;
      }

      final eventName = event?.name.isNotEmpty == true ? event!.name : widget.event.name;
      final studentId = widget.user.studentId.isNotEmpty ? widget.user.studentId : widget.user.username;
      final studentName = widget.user.fullName.isNotEmpty ? widget.user.fullName : widget.user.username;

      if (_pickingFaculty) return;
      _pickingFaculty = true;
      if (!mounted) return;
      final pickedFacultyId = await _pickFacultyForThisScan(context, eventId, studentId);
      _pickingFaculty = false;
      if (pickedFacultyId == null) {
        setState(() {
          _scanMessage = 'Select a faculty to continue.';
        });
        return;
      }

      final msg = await ref.read(attendanceProvider.notifier).markAttendance(
            eventId,
            eventName,
            studentId,
            studentName,
            widget.user.id,
            facultyId: pickedFacultyId,
          );

      setState(() {
        _scanMessage = msg;
      });
    } catch (e) {
      setState(() {
        _scanMessage = 'Scan error: $e';
      });
    } finally {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  Future<String?> _pickFacultyForThisScan(BuildContext ctx, String eventId, String studentId) async {
    final attendanceNotifier = ref.read(attendanceProvider.notifier);
    await attendanceNotifier.loadAttendance();
    final list = ref.read(attendanceProvider).value ?? const <AttendanceRecord>[];
    final now = DateTime.now();
    final open = list.where((r) {
      if (r.eventId != eventId) return false;
      if (r.studentId != studentId) return false;
      if (r.checkOutAt != null) return false;
      final checkIn = r.checkInAt ?? r.timestamp;
      return checkIn.year == now.year && checkIn.month == now.month && checkIn.day == now.day;
    }).cast<AttendanceRecord?>().firstWhere((r) => r != null, orElse: () => null);
    final stage = open == null ? 'Check-in' : 'Check-out';

    final rawFaculty = await ApiService.getFaculty();
    final faculty = rawFaculty.map((u) => User.fromJson(u)).toList();
    if (faculty.isEmpty) {
      if (mounted) {
        setState(() {
          _scanMessage = 'No faculty accounts found. Ask admin to create faculty accounts.';
        });
      }
      return null;
    }

    String selectedId = faculty.first.id;
    if (!ctx.mounted) return null;
    final picked = await showDialog<String>(
      context: ctx,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Choose faculty for $stage'),
          content: DropdownButtonFormField<String>(
            initialValue: selectedId,
            items: faculty
                .map(
                  (f) => DropdownMenuItem(
                    value: f.id,
                    child: Text(f.fullName.isEmpty ? f.username : f.fullName),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              setState(() => selectedId = v);
            },
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, selectedId), child: const Text('Continue')),
          ],
        ),
      ),
    );
    return picked;
  }
}

class _StandaloneQrScannerScreen extends ConsumerStatefulWidget {
  const _StandaloneQrScannerScreen({required this.user});
  final User user;

  @override
  ConsumerState<_StandaloneQrScannerScreen> createState() => _StandaloneQrScannerScreenState();
}

class _StandaloneQrScannerScreenState extends ConsumerState<_StandaloneQrScannerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        elevation: 0,
        flexibleSpace: const _AppBarGradientBg(),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF1F4FF),
              Color(0xFFF7F8FC),
              Color(0xFFF6F7FB),
            ],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: StudentScannerTab(user: widget.user),
          ),
        ),
      ),
    );
  }
}

class FacultyAttendanceTab extends ConsumerStatefulWidget {
  const FacultyAttendanceTab({super.key, required this.user});

  final User user;

  @override
  ConsumerState<FacultyAttendanceTab> createState() => _FacultyAttendanceTabState();
}

class _FacultyAttendanceTabState extends ConsumerState<FacultyAttendanceTab> {
  String _courseFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final attendanceState = ref.watch(attendanceProvider);
    return attendanceState.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (attendance) {
        final mineByFaculty = attendance
            .where((r) => r.checkedOutByFacultyId == widget.user.id || (r.checkOutAt == null && r.checkedInByFacultyId == widget.user.id))
            .toList();
        final courses = mineByFaculty
            .map((r) => r.studentCourse)
            .where((c) => c.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final filtered = _courseFilter == 'All'
            ? mineByFaculty
            : mineByFaculty.where((r) => r.studentCourse == _courseFilter).toList();
        final sorted = [...filtered]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

        return RefreshIndicator(
          onRefresh: () => ref.read(attendanceProvider.notifier).loadAttendance(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _courseFilter,
                          decoration: const InputDecoration(labelText: 'Course'),
                          items: [
                            const DropdownMenuItem(value: 'All', child: Text('All')),
                            ...courses.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _courseFilter = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (sorted.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'No attendance yet',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54),
                    ),
                  ),
                )
              else
                ...sorted.map((r) {
                  final checkIn = r.checkInAt ?? r.timestamp;
                  final expectedOut = checkIn.add(const Duration(minutes: attendanceTimeoutMinutes));
                  final out = r.checkOutAt ?? expectedOut;
                  final isOut = r.checkOutAt != null;
                  final courseLine = r.studentCourse.isEmpty && r.studentSection.isEmpty
                      ? ''
                      : '\n${r.studentCourse}${r.studentSection.isEmpty ? '' : ' • ${r.studentSection}'}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: ListTile(
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              Icons.how_to_reg,
                              color: Theme.of(context).colorScheme.onTertiaryContainer,
                            ),
                          ),
                          title: Text(r.eventName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            '${r.studentName} (${r.studentId})$courseLine\nIn: ${checkIn.toLocal()} • Out: ${out.toLocal()}',
                            style: const TextStyle(color: Colors.black54),
                          ),
                          trailing: _StatusChip(isOut: isOut),
                        ),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.isOut});

  final bool isOut;

  @override
  Widget build(BuildContext context) {
    final bg = isOut ? const Color(0xFFE6F7EE) : const Color(0xFFE8F0FF);
    final fg = isOut ? const Color(0xFF0F7A3A) : const Color(0xFF1E4DB7);
    final text = isOut ? 'OUT' : 'IN';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOut ? Icons.logout : Icons.login,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBackground extends StatelessWidget {
  const _TabBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF1F4FF),
            Color(0xFFF7F8FC),
            Color(0xFFF6F7FB),
          ],
        ),
      ),
      child: child,
    );
  }
}

class _AppBarGradientBg extends StatelessWidget {
  const _AppBarGradientBg();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryStart, Color(0xFF1d4ed8), AppColors.primaryEnd],
            ),
          ),
        ),
        Positioned.fill(
          child: Image.asset(
            AppThemeAssets.bgImage,
            fit: BoxFit.cover,
            opacity: const AlwaysStoppedAnimation(0.22),
          ),
        ),
      ],
    );
  }
}
