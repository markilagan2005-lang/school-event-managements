import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
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
      '1. Open Scan QR tab.\n'
          '2. Scan event QR when instructor allows.\n'
          '3. Select faculty for check-in/check-out.\n'
          '4. Review logs in My Attendance tab.',
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
      child: Scaffold(
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
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Theme.of(context).colorScheme.primary,
          actions: [
            IconButton(
              onPressed: () => _openSettingsSheet(context, ref, user),
              icon: const Icon(Icons.settings),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
          ],
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
      ),
    );
  }
}

class StudentHomeScreen extends ConsumerWidget {
  const StudentHomeScreen({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Student'),
              Text(
                user.username,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Theme.of(context).colorScheme.primary,
          actions: [
            IconButton(
              onPressed: () => _openSettingsSheet(context, ref, user),
              icon: const Icon(Icons.settings),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan QR'),
              Tab(icon: Icon(Icons.history), text: 'My Attendance'),
            ],
          ),
        ),
        body: _TabBackground(
          child: TabBarView(
            children: [
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
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: Theme.of(context).colorScheme.primary,
          actions: [
            IconButton(
              onPressed: () => _openSettingsSheet(context, ref, user),
              icon: const Icon(Icons.settings),
              style: IconButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
          ],
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
      appBar: AppBar(
        title: const Text('Faculty Verification'),
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                  FilledButton.icon(
                    onPressed: () => _showAddEventDialog(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
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
                      Expanded(
                        child: Text(
                          'After adding an event, show the Event QR to students for scanning.',
                          style: Theme.of(context).textTheme.bodyMedium,
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

  Future<void> _showAddEventDialog(BuildContext context) async {
    final nameController = TextEditingController();
    DateTime date = DateTime.now();
    String status = 'open';
    bool enableWindow = false;
    TimeOfDay startTime = const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 17, minute: 0);
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Event'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Event name'),
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
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
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
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
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
                final created = await ref.read(eventProvider.notifier).addEvent(
                      name,
                      date,
                      status: status,
                      startAt: startAt,
                      endAt: endAtDt,
                    );
                if (!context.mounted) return;
                Navigator.pop(context);
                if (created != null) {
                  await _showEventQr(context, created);
                }
              },
              child: const Text('Add'),
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
                          'Export (Name + In/Out)',
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
                            'In: ${checkIn.toLocal()}\nOut: ${(checkOut ?? checkIn.add(const Duration(minutes: attendanceTimeoutMinutes))).toLocal()}',
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
    buffer.writeln('studentName,checkInAt,checkOutAt');
    for (final r in attendance) {
      final checkIn = r.checkInAt ?? r.timestamp;
      buffer.writeln([
        _csvCell(r.studentName),
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit user',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditUserDialog(
                                    context,
                                    u,
                                    canEditUserId: canEditUserId,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Reset password',
                                  icon: const Icon(Icons.lock_reset_outlined),
                                  onPressed: () => _showAdminResetPasswordDialog(context, u),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: canDelete
                                      ? () async {
                                          await ApiService.deleteUser(u.id);
                                          setState(() => _future = _loadUsers());
                                        }
                                      : null,
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (u.role == 'faculty' && !u.isApproved)
                                  IconButton(
                                    tooltip: 'Approve faculty',
                                    icon: const Icon(Icons.verified),
                                    onPressed: () async {
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
                                    },
                                  ),
                                IconButton(
                                  tooltip: 'Edit user',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showEditUserDialog(
                                    context,
                                    u,
                                    canEditUserId: canEditUserId,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Reset password',
                                  icon: const Icon(Icons.lock_reset_outlined),
                                  onPressed: () => _showAdminResetPasswordDialog(context, u),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: canDelete
                                      ? () async {
                                          await ApiService.deleteUser(u.id);
                                          setState(() => _future = _loadUsers());
                                        }
                                      : null,
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
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'student', child: Text('Student')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'faculty', child: Text('Faculty')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setStateDialog(() => role = value);
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
                  );
                  if (!context.mounted) return;
                  Navigator.pop(dialogContext);
                  setState(() => _future = _loadUsers());
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('User updated')),
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
  bool _processing = false;
  String _message = 'Scan a QR code to mark attendance.';
  int _lastRefreshMs = 0;
  bool _pickingFaculty = false;

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
                    border: Border.all(color: const Color(0xFFE6E8F0)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: MobileScanner(
                    onDetect: (capture) => _onDetect(capture, events),
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
