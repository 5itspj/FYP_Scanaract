import 'package:flutter/material.dart';

class DataOverviewScreen extends StatelessWidget {
  const DataOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data overview'),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Data overview',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildInfoItem('Total number of tests', '45'),
            _buildInfoItem('Number of consecutive testing days', '7'),
            _buildInfoItem('Registration time', '16/7/2025'),
            _buildInfoItem('Current number of consecutive detection days', '7'),
            _buildInfoItem('Frequency of testing this week', '2/3 times'),
            _buildInfoItem('Average detection interval', '7 days'),
            _buildInfoItem('Core Health Index', '70'),
            _buildInfoItem('Summary of long-term trends', 'slowly improving'),
            _buildInfoItem('Data Stability', 'High'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16, color: Colors.black87)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}