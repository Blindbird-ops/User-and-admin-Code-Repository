import 'dart:convert';
import 'package:http/http.dart' as http;

class AnnouncementService {
  final String token;

  AnnouncementService({required this.token});

  Future<bool> postAnnouncement({
    required String title, // The "What"
    required String message,
    required String when, // New
    required String where, // New
    required String imageUrl, // New
  }) async {
    final url = "https://mabskie-47c24-default-rtdb.firebaseio.com/announcements.json?auth=$token";
    
    final announcementData = {
      'title': title,
      'message': message,
      'when': when,
      'where': where,
      'imageUrl': imageUrl,
      'timestamp': DateTime.now().toIso8601String(),
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        body: json.encode(announcementData),
      );
      return response.statusCode == 200;
    } catch (error) {
      print("Error posting announcement: $error");
      return false;
    }
  }
}