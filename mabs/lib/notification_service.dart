import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

// --- 1. BACKGROUND HANDLER (Top Level) ---
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Handling a background message: ${message.messageId}");
}

class NotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await AwesomeNotifications().initialize(
      null, 
      [
        NotificationChannel(
          channelGroupKey: 'basic_channel_group',
          channelKey: 'announcements_channel',
          channelName: 'Announcements',
          channelDescription: 'Notifications for new barangay announcements',
          defaultColor: const Color(0xFF9D50DD),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          criticalAlerts: true,
        ),
        NotificationChannel(
          channelGroupKey: 'basic_channel_group',
          channelKey: 'document_updates',
          channelName: 'Document Updates',
          channelDescription: 'Notifications for document status changes',
          defaultColor: const Color(0xFF009688),
          ledColor: Colors.white,
          importance: NotificationImportance.Max,
          channelShowBadge: true,
          playSound: true,
          criticalAlerts: true,
        )
      ],
      debug: true,
    );

    // Register Background Handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Initialize FCM Settings and Foreground Listener
    await _initializeFCM();
    
    // NOTE: We REMOVED AwesomeNotifications().setListeners() from here.
    // Your UserScreen now sets the listeners to handle navigation.
  }

  static Future<void> _initializeFCM() async {
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted permission');
      
      await _firebaseMessaging.subscribeToTopic('all_users');

      // Token Management
      String? token = await _firebaseMessaging.getToken();
      if (token != null) saveTokenToDatabase(token); 

      _firebaseMessaging.onTokenRefresh.listen(saveTokenToDatabase); 

      // --- FOREGROUND MESSAGES ONLY ---
      // This part is crucial: It manually shows a notification banner when the app is OPEN.
      // If we remove this, you won't see banners while using the app.
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print("Received Foreground Message: ${message.notification?.title}");
        
        if (message.notification != null) {
          String channelKey = 'announcements_channel';
          if (message.data['type'] == 'document') {
            channelKey = 'document_updates';
          }

          AwesomeNotifications().createNotification(
            content: NotificationContent(
              id: message.hashCode,
              channelKey: channelKey, 
              title: message.notification!.title,
              body: message.notification!.body,
              notificationLayout: NotificationLayout.BigText,
              // We pass the payload so UserScreen can read it if clicked
              payload: message.data.map((key, value) => MapEntry(key, value.toString())),
            ),
          );
        }
      });

      // REMOVED: onMessageOpenedApp (Now handled in UserScreen)
      // REMOVED: getInitialMessage (Now handled in UserScreen)
    }
  }

  static Future<void> saveTokenToDatabase(String token) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DatabaseReference ref = FirebaseDatabase.instance.ref("users/${user.uid}/fcmToken");
      await ref.set(token);
      print("FCM Token saved for user: ${user.uid}");
    }
  }

  // --- MANUAL TRIGGERS & HELPERS ---

  static Future<void> checkPermissions(BuildContext context) async {
    bool isAllowed = await AwesomeNotifications().isNotificationAllowed();
    if (!isAllowed) {
      if (context.mounted) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
    }
  }

  static Future<void> showAnnouncementNotification({required String title, required String body}) async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'announcements_channel',
        title: '📢 $title',
        body: body,
        notificationLayout: NotificationLayout.BigText,
        wakeUpScreen: true,
      ),
    );
  }

  static Future<void> showVerificationNotification() async {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'document_updates', 
        title: '🎉 Congratulations! You are Verified',
        body: 'Your identity verification has been approved. You can now access all app features.',
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
        category: NotificationCategory.Status,
        payload: {'navigate': 'true', 'type': 'profile'}, 
      ),
    );
  }

  static Future<void> showStatusUpdateNotification({required String docType, required String status}) async {
    String emoji = "📄";
    if (status.toLowerCase().contains('approve') || status.toLowerCase().contains('ready')) emoji = "✅";
    if (status.toLowerCase().contains('reject')) emoji = "❌";

    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'document_updates',
        title: '$emoji Update: $docType',
        body: 'Your request is now: $status. Tap to view details.',
        notificationLayout: NotificationLayout.Default,
        wakeUpScreen: true,
        payload: {'navigate': 'true', 'type': 'document'},
      ),
    );
  }
}