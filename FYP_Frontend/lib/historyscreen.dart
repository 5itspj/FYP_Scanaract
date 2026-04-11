import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'report_detail_screen.dart';
import 'custom_page_route.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadUserAvatar();
  }

  Future<void> _loadUserAvatar() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('profiles')
          .select('avatar_url')
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _avatarUrl = data['avatar_url'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Failed to load avatar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultAvatar = 'https://randomuser.me/api/portraits/women/44.jpg';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'History',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white,
              child: ClipOval(
                child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                    ? Image.network(
                        _avatarUrl!,
                        fit: BoxFit.cover,
                        width: 44,
                        height: 44,
                        errorBuilder: (_, __, ___) => Image.network(defaultAvatar, fit: BoxFit.cover),
                      )
                    : Image.network(defaultAvatar, fit: BoxFit.cover, width: 44, height: 44),
              ),
            ),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: historyRecords.length,
        itemBuilder: (context, index) {
          final record = historyRecords[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 1.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              leading: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.pink.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.access_time_rounded, color: Colors.pinkAccent, size: 28),
              ),
              title: Text(
                'Inspection results: ${record['date']}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('● ${record['relative']}', style: TextStyle(color: Colors.grey.shade700)),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 28),
              onTap: () {
                Navigator.push(
                  context,
                  FadeScaleRoute(
                    page: ReportDetailScreen(
                      date: record['date'],
                      reportData: record['report'],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  final List<Map<String, dynamic>> historyRecords = [
    {
      'date': '2025.9.25',
      'relative': '2 days ago',
      'report': {
        'title': '[This test report - 2025-9-25]',
        'index': '78/100',
        'indicators': [
          {'name': 'Turbidity density', 'value': 'Level 2 (mild)', 'arrow': '→', 'color': Colors.orange},
          {'name': 'Turbidity range', 'value': '15%', 'arrow': '↓', 'color': Colors.green},
          {'name': 'Core Hardness', 'value': 'Level II', 'arrow': '→', 'color': Colors.orange},
          {'name': 'Contrast sensitivity', 'value': '85 points', 'arrow': '↑', 'color': Colors.green},
          {'name': 'Scattered light index', 'value': '3.5', 'arrow': '↓', 'color': Colors.green},
          {'name': 'Predicted corrected visual acuity', 'value': '0.7', 'arrow': '→', 'color': Colors.orange},
          {'name': 'Color identification', 'value': 'Deviation value 4.1', 'arrow': '↓', 'color': Colors.green},
        ],
      },
    },
    {
      'date': '2025.9.24',
      'relative': '3 days ago',
      'report': { /* ... */ },
    },
    {
      'date': '2025.9.23',
      'relative': '4 days ago',
      'report': { /* ... */ },
    },
  ];
}