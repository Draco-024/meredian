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

  // Made nullable so it doesn't instantiate on the Web!
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

  Future<void> requestPermissions() async {
    if (kIsWeb || _localNotificationsPlugin == null) return; 

    try {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotificationsPlugin!.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
        await androidImplementation.requestExactAlarmsPermission();
      }
    } catch (e) {
      debugPrint("Meridian Permission Error: $e");
    }
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  Future<void> scheduleSmartReminders(int intervalHours, String? customSoundPath) async {
    if (kIsWeb || _localNotificationsPlugin == null) return; 

    try {
      await cancelAllReminders(); 

      String channelId = customSoundPath != null 
          ? 'meridian_custom_${DateTime.now().millisecondsSinceEpoch}' 
          : 'meridian_default';

      AndroidNotificationSound? notificationSound;
      
      if (!kIsWeb && customSoundPath != null) {
        final file = File(customSoundPath);
        if (file.existsSync()) {
          notificationSound = UriAndroidNotificationSound("file://$customSoundPath");
        }
      }

      int startHour = 8; 
      int endHour = 22;  
      int notificationId = 0;

      for (int hour = startHour; hour <= endHour; hour += intervalHours) {
        await _localNotificationsPlugin!.zonedSchedule(
          notificationId++,
          'Meridian',
          'Maintain your flow. Time to hydrate.',
          _nextInstanceOfTime(hour, 0),
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              'Meridian Vitality',
              channelDescription: 'Premium daily hydration intervals',
              importance: Importance.max,
              priority: Priority.high,
              enableVibration: true,
              color: const Color(0xFF000000), 
              playSound: true,
              sound: notificationSound,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time,
        );
      }
    } catch (e) {
      debugPrint("Meridian Scheduling Error: $e");
    }
  }

  Future<void> cancelAllReminders() async {
    if (kIsWeb || _localNotificationsPlugin == null) return; 
    await _localNotificationsPlugin!.cancelAll();
  }
}