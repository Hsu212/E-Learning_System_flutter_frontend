import 'main.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

class MaterialDetailScreen extends StatefulWidget {
  final Classwork material;
  const MaterialDetailScreen({super.key, required this.material});
  @override
  State<MaterialDetailScreen> createState() => _MaterialDetailScreenState();
}

class _MaterialDetailScreenState extends State<MaterialDetailScreen> {
  @override
  void initState() {
    super.initState();
    final user = context.read<AppState>().currentUser!;
    context.read<AppState>().apiService!.logView(user.id, widget.material.id, 'view');
  }

  void _showAnalytics() {
    showModalBottomSheet(
      context: context, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => FutureBuilder(
      future: context.read<AppState>().apiService!.getContentViews(widget.material.id),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final list = snapshot.data as List<Map<String, dynamic>>;
        if (list.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("No views yet")));
        
        return Column(
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text("View Analytics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
            Expanded(child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) => ListTile(
                leading: CircleAvatar(child: Text(list[i]['name'][0])),
                title: Text(list[i]['name']),
                subtitle: Text(DateFormat('MMM d, h:mm a').format(DateTime.parse(list[i]['time']))),
              ),
            )),
          ],
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isInstructor = context.read<AppState>().currentUser!.role == UserRole.instructor;
    
    return Scaffold(
      appBar: AppBar(
        title: null, // Minimalist
        actions: [
          if (isInstructor)
            IconButton(
              icon: const Icon(Icons.bar_chart),
              tooltip: "Analytics",
              onPressed: _showAnalytics,
            ),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: (){})
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.book, color: AppColors.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.material.title, style: const TextStyle(fontSize: 22, color: AppColors.textDark, fontWeight: FontWeight.w500)),
                      Text(
                        'Posted ${DateFormat('MMM d').format(widget.material.postedDate)}', 
                        style: const TextStyle(color: AppColors.textLight, fontSize: 13)
                      ),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 24),
            const Divider(height: 1),
            const SizedBox(height: 24),
            
            // Description
            Text(
              widget.material.description.isEmpty ? "No description" : widget.material.description, 
              style: const TextStyle(fontSize: 15, height: 1.5, color: Colors.black87)
            ),
            
            const SizedBox(height: 32),
            
            // Attachments
            if (widget.material.attachmentUrls.isNotEmpty) ...[
               const Text("Attachments", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
               const SizedBox(height: 16),
               Wrap(
                 spacing: 12,
                 runSpacing: 12,
                 children: widget.material.attachmentUrls.map((url) {
                   return Container(
                     width: double.infinity,
                     decoration: BoxDecoration(
                       border: Border.all(color: AppColors.divider),
                       borderRadius: BorderRadius.circular(8),
                     ),
                     child: ListTile(
                       contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                       leading: const Icon(Icons.insert_drive_file, color: Colors.redAccent), // PDF style
                       title: Text(url.split('/').last, style: const TextStyle(fontWeight: FontWeight.w500)),
                       trailing: const Icon(Icons.open_in_new, size: 20, color: AppColors.textLight),
                       onTap: () {
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening...")));
                       },
                     ),
                   );
                 }).toList(),
               )
            ]
          ],
        ),
      ),
    );
  }
}