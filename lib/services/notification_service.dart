import 'dart:io';
import 'package:flutter/material.dart'; 
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  FlutterLocalNotificationsPlugin? _localNotificationsPlugin;
  bool _isInitialized = false;

  Future<void> init() async {
    if (kIsWeb) return; 
    if (_isInitialized) return;

    try {
      _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
      tz.initializeTimeZones();

      const AndroidInitializationSettings androidInitSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings iosInitSettings =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidInitSettings,
        iOS: iosInitSettings,
      );

      await _localNotificationsPlugin!.initialize(initSettings);
      _isInitialized = true;
    } catch (e) {
      debugPrint("Meridian Notification Error: $e");
    }
  }

  // Forces Android 14 to prompt for Exact Alarm Permissions
  Future<void> requestPermissions() async {
    if (kIsWeb || _localNotificationsPlugin == null) return; 

    try {
      if (Platform.isAndroid) {
        final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
            _localNotificationsPlugin!.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();

        if (androidImplementation != null) {
          await androidImplementation.requestNotificationsPermission();
          await androidImplementation.requestExactAlarmsPermission();
        }
      }
    } catch (e) {
      debugPrint("Meridian Permission Error: $e");
    }
  }

  Future<void> scheduleSmartReminders(int intervalHours, String toneType, String? customSoundPath) async {
    if (kIsWeb || _localNotificationsPlugin == null) {
      return; 
    }

    try {
      // Clear old alarms before setting new ones
      await cancelAllReminders(); 

      String channelId = 'meridian_test_channel_${toneType}_${customSoundPath?.hashCode ?? 0}';

      AndroidNotificationSound? notificationSound;
      
      if (toneType == 'custom' && customSoundPath != null && !kIsWeb) {
        final file = File(customSoundPath);
        if (file.existsSync()) {
          notificationSound = UriAndroidNotificationSound("file://$customSoundPath");
        }
      } else if (toneType == 'deep_synth' || toneType == 'lux_chime' || toneType == 'zen_bowl') {
        notificationSound = RawResourceAndroidNotificationSound(toneType);
      } 

      int notificationId = 0;

      // ---------------------------------------------------------
      // 🔥 TEMPORARY 1-MINUTE EMULATOR TEST LOGIC 🔥
      // Schedules 3 alarms: 1 min, 2 min, and 3 min from right now
      // ---------------------------------------------------------
      final DateTime now = DateTime.now();
      
      for (int i = 1; i <= 3; i++) {
        DateTime testTime = now.add(Duration(minutes: i));
        tz.TZDateTime scheduledDate = tz.TZDateTime.from(testTime, tz.local);

        await _localNotificationsPlugin!.zonedSchedule(
          notificationId++,
          'Meridian TEST',
          'Test Reminder ($i min). It works!',
          scheduledDate,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              'Meridian Test Channel',
              importance: Importance.max,
              priority: Priority.high,
              enableVibration: true,
              color: const Color(0xFF000000), 
              playSound: true,
              sound: notificationSound,
              category: AndroidNotificationCategory.reminder,
              visibility: NotificationVisibility.public,
              fullScreenIntent: true, 
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          // Removed daily repeat purely for this immediate test
        );
      }
      // ---------------------------------------------------------

    } catch (e) {
      debugPrint("Meridian Scheduling Error: $e");
    }
  }

  Future<void> cancelAllReminders() async {
    if (kIsWeb || _localNotificationsPlugin == null) return; 
    await _localNotificationsPlugin!.cancelAll();
  }
}