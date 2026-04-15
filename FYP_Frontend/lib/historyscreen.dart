import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _historyRecords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('examinations')
          .select('id, health_index, image_url, uploaded_at, notes')
          .eq('user_id', user.id)
          .order('uploaded_at', ascending: false);

      setState(() {
        _historyRecords = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Failed to load history: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'History',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyRecords.isEmpty
              ? const Center(
                  child: Text(
                    'No scan records yet.\nGo to Scan page to start.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _historyRecords.length,
                  itemBuilder: (context, index) {
                    final record = _historyRecords[index];
                    final imageUrl = record['image_url'] as String?;
                    final uploadedAt = record['uploaded_at'] != null
                        ? DateTime.parse(record['uploaded_at']).toLocal()
                        : null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 显示照片
                          if (imageUrl != null && imageUrl.isNotEmpty)
                            ClipRRect(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                              child: Image.network(
                                imageUrl,
                                height: 220,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  height: 220,
                                  color: Colors.grey[200],
                                  child: const Center(
                                    child: Icon(Icons.broken_image, size: 60, color: Colors.grey),
                                  ),
                                ),
                              ),
                            ),

                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  uploadedAt != null
                                      ? 'Inspection ${uploadedAt.month.toString().padLeft(2, '0')}/${uploadedAt.day.toString().padLeft(2, '0')} '
                                          '${uploadedAt.hour.toString().padLeft(2, '0')}:${uploadedAt.minute.toString().padLeft(2, '0')}'
                                      : 'Inspection',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Health Index: ${record['health_index'] ?? "N/A"}',
                                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                                ),
                                if (record['notes'] != null && record['notes'].toString().isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      record['notes'],
                                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}