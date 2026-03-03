import 'dart:io';
import 'dart:ui'; 
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'services/notification_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  runApp(const MeridianApp());
}

class MeridianApp extends StatelessWidget {
  const MeridianApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meridian',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black, useMaterial3: true),
      home: const MeridianDashboard(),
    );
  }
}

class MeridianDashboard extends StatefulWidget {
  const MeridianDashboard({super.key});

  @override
  State<MeridianDashboard> createState() => _MeridianDashboardState();
}

class _MeridianDashboardState extends State<MeridianDashboard> with TickerProviderStateMixin {
  static const double minGoal = 1000.0;
  static const double maxGoal = 10000.0;

  double _dailyGoal = 3000.0;
  double _currentWater = 0.0;
  bool _remindersActive = false;
  int _reminderInterval = 2; 
  String? _customSoundPath; 
  String _customSoundName = 'Default'; 
  
  bool _climateOverrideApplied = false;
  List<double> _weeklyHistory = List.filled(7, 0.0);
  
  late SharedPreferences _prefs;

  late AnimationController _breathingController;
  late AnimationController _waveController;
  late AnimationController _popController;
  late AnimationController _particleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAppBackground(); 

    _breathingController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
    _waveController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    
    _popController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _popController, curve: Curves.elasticOut),
    );
  }

  Future<void> _initializeAppBackground() async {
    try {
      await NotificationService().init();
    } catch (e) {
      debugPrint("Native Init Ignored: $e");
    }
    await _initData();
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _waveController.dispose();
    _popController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      
      setState(() {
        double savedGoal = _prefs.getDouble('dailyGoal') ?? 3000.0;
        _dailyGoal = savedGoal.clamp(minGoal, maxGoal);
        _remindersActive = _prefs.getBool('remindersActive') ?? false;
        _reminderInterval = _prefs.getInt('reminderInterval') ?? 2;
        _climateOverrideApplied = _prefs.getBool('climateOverride') ?? false;
        
        _customSoundPath = _prefs.getString('customSoundPath');
        _customSoundName = _prefs.getString('customSoundName') ?? 'Default';

        String historyJson = _prefs.getString('weeklyHistory') ?? '[]';
        List<dynamic> loadedHistory = jsonDecode(historyJson);
        if (loadedHistory.length == 7) {
          _weeklyHistory = loadedHistory.map((e) => (e as num).toDouble()).toList();
        }
        
        String lastDate = _prefs.getString('lastDate') ?? '';
        String today = DateTime.now().toIso8601String().substring(0, 10);
        
        if (lastDate != today) {
          _weeklyHistory.removeAt(0);
          _weeklyHistory.add(0.0);
          _prefs.setString('weeklyHistory', jsonEncode(_weeklyHistory));
          
          _currentWater = 0.0;
          _climateOverrideApplied = false;
          _prefs.setString('lastDate', today);
          _prefs.setDouble('currentWater', 0.0);
          _prefs.setBool('climateOverride', false);
        } else {
          _currentWater = (_prefs.getDouble('currentWater') ?? 0.0).toDouble();
        }
      });
    } catch (e) {
      debugPrint("Data Load Error: $e");
    }
  }

  void _addWater(double amount) async {
    try { Haptics.vibrate(HapticsType.medium); } catch (_) {}
    _popController.forward(from: 0.0);

    setState(() {
      _currentWater += amount;
      if (_currentWater > _dailyGoal) _currentWater = _dailyGoal; 
      _weeklyHistory[6] = _currentWater; 
    });
    
    await _prefs.setDouble('currentWater', _currentWater);
    await _prefs.setString('weeklyHistory', jsonEncode(_weeklyHistory));
    
    if (_currentWater >= _dailyGoal) {
      try { Haptics.vibrate(HapticsType.success); } catch (_) {}
    }
  }

  void _updateReminders() {
    if (_remindersActive) {
      NotificationService().scheduleSmartReminders(_reminderInterval, _customSoundPath);
    } else {
      NotificationService().cancelAllReminders();
    }
  }

  void _applyClimateOverride() {
    Haptics.vibrate(HapticsType.success);
    setState(() {
      _dailyGoal = (_dailyGoal + 500).clamp(minGoal, maxGoal);
      _climateOverrideApplied = true;
    });
    _prefs.setDouble('dailyGoal', _dailyGoal);
    _prefs.setBool('climateOverride', true);
  }

  Future<void> _pickCustomAudio() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Custom Tones are only supported on the mobile app.', style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: const Color(0xFF0F172A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return; 
    }
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        Haptics.vibrate(HapticsType.success);
        
        File pickedFile = File(result.files.single.path!);
        String fileName = result.files.single.name;
        final appDir = await getApplicationDocumentsDirectory();
        final savedFile = await pickedFile.copy('${appDir.path}/$fileName');

        setState(() {
          _customSoundPath = savedFile.path;
          _customSoundName = fileName.split('.').first.replaceAll('_', ' ');
          if (_customSoundName.length > 12) _customSoundName = '${_customSoundName.substring(0, 10)}...';
        });

        _prefs.setString('customSoundPath', _customSoundPath!);
        _prefs.setString('customSoundName', _customSoundName);
        _updateReminders(); 
      }
    } catch (e) {
      debugPrint("Error picking audio: $e");
    }
  }

  void _resetToDefaultAudio() {
    Haptics.vibrate(HapticsType.selection);
    setState(() {
      _customSoundPath = null;
      _customSoundName = 'Default';
    });
    _prefs.remove('customSoundPath');
    _prefs.setString('customSoundName', 'Default');
    _updateReminders();
  }

  void _showCustomWaterSheet(Color primaryColor) {
    double customAmount = 250.0;
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, isScrollControlled: true, 
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: EdgeInsets.only(top: 32, left: 32, right: 32, bottom: MediaQuery.of(context).viewInsets.bottom + 40),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withOpacity(0.7),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
                  border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 32),
                    Text('CUSTOM LOG', style: GoogleFonts.inter(letterSpacing: 4.0, fontSize: 12, color: Colors.white54)),
                    const SizedBox(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(customAmount.toInt().toString(), style: GoogleFonts.inter(color: primaryColor, fontSize: 72, fontWeight: FontWeight.w200, letterSpacing: -3.0)),
                        const SizedBox(width: 8),
                        Text('ML', style: GoogleFonts.inter(fontSize: 16, color: Colors.white54, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 40),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(activeTrackColor: primaryColor, inactiveTrackColor: Colors.white12, thumbColor: primaryColor, trackHeight: 2.0, overlayShape: SliderComponentShape.noOverlay),
                      child: Slider(
                        value: customAmount, min: 10, max: 2000, divisions: 99,
                        onChanged: (val) {
                          setModalState(() => customAmount = val);
                          if (val % 50 == 0) Haptics.vibrate(HapticsType.selection);
                        },
                      ),
                    ),
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        _addWater(customAmount);
                      },
                      child: Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: primaryColor.withOpacity(0.3))),
                        child: Center(child: Text('LOG WATER', style: GoogleFonts.inter(color: primaryColor, fontWeight: FontWeight.w600, letterSpacing: 1.5, fontSize: 14))),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double targetProgress = (_currentWater / _dailyGoal).clamp(0.0, 1.0);
    bool isGoalMet = _currentWater >= _dailyGoal;
    Color primaryColor = isGoalMet ? const Color(0xFFD4AF37) : const Color(0xFF06B6D4);

    return Scaffold(
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _waveController,
            builder: (context, child) {
              return Positioned.fill(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: targetProgress),
                  duration: const Duration(milliseconds: 1500), curve: Curves.easeInOutCubic,
                  builder: (context, fillHeight, child) {
                    return CustomPaint(painter: AmbientWavePainter(phase: _waveController.value * 2 * math.pi, fillPercentage: fillHeight, color: isGoalMet ? const Color(0xFFD4AF37) : const Color(0xFF0EA5E9)));
                  },
                ),
              );
            },
          ),
          AnimatedBuilder(
            animation: _breathingController,
            builder: (context, child) {
              return Positioned(
                top: MediaQuery.of(context).size.height * 0.1, left: -50, right: -50,
                child: Opacity(
                  opacity: 0.4 + (_breathingController.value * 0.4),
                  child: Container(
                    height: 400,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [isGoalMet ? const Color(0xFFD4AF37).withOpacity(0.15) : const Color(0xFF06B6D4).withOpacity(0.3), Colors.transparent], stops: const [0.0, 1.0])),
                  ),
                ),
              );
            }
          ),
          if (isGoalMet)
            AnimatedBuilder(
              animation: _particleController,
              builder: (context, child) {
                return Positioned.fill(
                  child: CustomPaint(painter: GoldenParticlePainter(time: _particleController.value * 2 * math.pi)),
                );
              }
            ),
          
          SafeArea(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('M E R I D I A N', style: GoogleFonts.inter(letterSpacing: 4.0, fontSize: 12, color: Colors.white54)),
                            Icon(Icons.spa_rounded, color: isGoalMet ? primaryColor : Colors.white38, size: 20),
                          ],
                        ),
                        const SizedBox(height: 40),
                        ScaleTransition(
                          scale: _scaleAnimation,
                          child: SizedBox(
                            height: 300, width: 300,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween<double>(begin: 0, end: targetProgress),
                                  duration: const Duration(milliseconds: 1200), curve: Curves.easeOutCubic,
                                  builder: (context, value, child) {
                                    return CustomPaint(size: const Size(300, 300), painter: PremiumRingPainter(progress: value, color: primaryColor));
                                  },
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0, end: _currentWater),
                                      duration: const Duration(milliseconds: 1000), curve: Curves.easeOutCubic,
                                      builder: (context, waterValue, child) {
                                        return Text(waterValue.toInt().toString(), style: GoogleFonts.inter(color: primaryColor, fontSize: 56, fontWeight: FontWeight.w200, letterSpacing: -2.0));
                                      },
                                    ),
                                    Text(isGoalMet ? 'OPTIMIZED' : 'MILLILITERS', style: GoogleFonts.inter(letterSpacing: 2.0, fontSize: 10, color: isGoalMet ? primaryColor.withOpacity(0.8) : Colors.white54)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildGlassButton('+ 150ml', () => _addWater(150), isGoalMet, primaryColor),
                            _buildGlassButton('+ 250ml', () => _addWater(250), isGoalMet, primaryColor),
                            _buildGlassButton('+ 500ml', () => _addWater(500), isGoalMet, primaryColor),
                            GestureDetector(
                              onTap: () {
                                Haptics.vibrate(HapticsType.selection);
                                _showCustomWaterSheet(primaryColor);
                              },
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    height: 54, width: 54, decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: primaryColor.withOpacity(0.2))),
                                    child: Icon(Icons.edit_rounded, color: primaryColor, size: 20),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        if (!_climateOverrideApplied && !isGoalMet)
                          Container(
                            margin: const EdgeInsets.only(bottom: 20), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(color: const Color(0xFFEA580C).withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEA580C).withOpacity(0.3))),
                            child: Row(
                              children: [
                                const Icon(Icons.wb_sunny_rounded, color: Color(0xFFEA580C), size: 20),
                                const SizedBox(width: 12),
                                Expanded(child: Text('High local temperatures detected. +500ml recommended today.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12))),
                                GestureDetector(
                                  onTap: _applyClimateOverride,
                                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFEA580C).withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: Text('APPLY', style: GoogleFonts.inter(color: const Color(0xFFEA580C), fontWeight: FontWeight.bold, fontSize: 11))),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(color: const Color(0xFF0F172A).withOpacity(0.6), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white12, width: 1)),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Text('Daily Goal', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
                                  const Spacer(),
                                  Text('${_dailyGoal.toInt()} ML', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(activeTrackColor: Colors.white, inactiveTrackColor: Colors.white12, thumbColor: Colors.white, trackHeight: 2.0, overlayShape: SliderComponentShape.noOverlay),
                                child: Slider(
                                  value: _dailyGoal, min: minGoal, max: maxGoal, divisions: 45,
                                  onChanged: (val) {
                                    setState(() => _dailyGoal = val);
                                    _prefs.setDouble('dailyGoal', val);
                                    Haptics.vibrate(HapticsType.selection);
                                  },
                                ),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Divider(color: Colors.white12, height: 1)),
                              Row(
                                children: [
                                  Text('Smart Offline Reminders', style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
                                  const Spacer(),
                                  Switch(
                                    value: _remindersActive, activeColor: Colors.black, activeTrackColor: primaryColor, inactiveTrackColor: Colors.white12, inactiveThumbColor: Colors.white54,
                                    onChanged: (val) async {
                                      Haptics.vibrate(HapticsType.selection);
                                      
                                      // 🔥 THIS IS WHERE THE PERMISSION IS TRIGGERED FOR THE FIRST TIME
                                      if (val == true) {
                                        await NotificationService().requestPermissions();
                                      }

                                      setState(() => _remindersActive = val);
                                      _prefs.setBool('remindersActive', val);
                                      _updateReminders();
                                    },
                                  ),
                                ],
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 300), curve: Curves.easeInOutCubic,
                                child: _remindersActive ? Column(
                                  children: [
                                    const Padding(padding: EdgeInsets.symmetric(vertical: 12.0), child: Divider(color: Colors.white12, height: 1)),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Frequency', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                                        Row(
                                          children: [1, 2, 3, 4].map((hours) => GestureDetector(
                                            onTap: () {
                                              Haptics.vibrate(HapticsType.selection);
                                              setState(() => _reminderInterval = hours);
                                              _prefs.setInt('reminderInterval', hours);
                                              _updateReminders();
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(milliseconds: 200), margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(color: _reminderInterval == hours ? primaryColor : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                                              child: Text('${hours}h', style: GoogleFonts.inter(color: _reminderInterval == hours ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                                            ),
                                          )).toList(),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    
                                    // 🔥 THE CUSTOM TONE UI IS NOW UNCLOAKED AND VISIBLE EVERYWHERE
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text('Custom Tone', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                                        Row(
                                          children: [
                                            if (_customSoundPath != null)
                                              GestureDetector(
                                                onTap: _resetToDefaultAudio,
                                                child: Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 14, color: Colors.redAccent)),
                                              ),
                                            GestureDetector(
                                              onTap: _pickCustomAudio,
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 200), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: _customSoundPath != null ? primaryColor : Colors.white12)),
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.library_music_rounded, size: 14, color: _customSoundPath != null ? primaryColor : Colors.white54),
                                                    const SizedBox(width: 6),
                                                    Text(_customSoundName.toUpperCase(), style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ) : const SizedBox.shrink(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 40),
                        SizedBox(
                          height: 80,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('VITALITY LEDGER', style: GoogleFonts.inter(letterSpacing: 2.0, fontSize: 10, color: Colors.white38)),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(7, (index) {
                                  double dayVal = _weeklyHistory[index];
                                  double barHeight = (dayVal / _dailyGoal).clamp(0.1, 1.0) * 50; 
                                  bool met = dayVal >= _dailyGoal;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 800), curve: Curves.easeOutCubic, width: 30, height: barHeight,
                                    decoration: BoxDecoration(color: met ? const Color(0xFFD4AF37) : (index == 6 ? primaryColor : Colors.white12), borderRadius: BorderRadius.circular(6)),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassButton(String label, VoidCallback onTap, bool isGoalMet, Color primaryColor) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(color: primaryColor.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: primaryColor.withOpacity(0.2))),
            child: Text(label, style: GoogleFonts.inter(color: primaryColor, fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// PAINTERS
// ----------------------------------------------------------------------
class PremiumRingPainter extends CustomPainter {
  final double progress; final Color color;
  PremiumRingPainter({required this.progress, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    Offset center = Offset(size.width / 2, size.height / 2); double radius = size.width / 2;
    Paint trackPaint = Paint()..color = Colors.white.withOpacity(0.05)..style = PaintingStyle.stroke..strokeWidth = 2.0;
    canvas.drawCircle(center, radius, trackPaint);
    Paint progressPaint = Paint()..shader = SweepGradient(colors: [color.withOpacity(0.3), color], stops: const [0.0, 1.0], transform: const GradientRotation(-math.pi / 2)).createShader(Rect.fromCircle(center: center, radius: radius))..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 6.0;
    Paint glowPaint = Paint()..color = color.withOpacity(0.25)..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 14.0..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);
    double sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweepAngle, false, glowPaint);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -math.pi / 2, sweepAngle, false, progressPaint);
  }
  @override bool shouldRepaint(covariant PremiumRingPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.color != color;
}

class AmbientWavePainter extends CustomPainter {
  final double phase, fillPercentage; final Color color;
  AmbientWavePainter({required this.phase, required this.fillPercentage, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    double targetHeight = size.height - (size.height * (0.1 + (fillPercentage * 0.8)));
    Paint wave1 = Paint()..color = color.withOpacity(0.03)..style = PaintingStyle.fill;
    Paint wave2 = Paint()..color = color.withOpacity(0.05)..style = PaintingStyle.fill;
    Paint wave3 = Paint()..color = color.withOpacity(0.08)..style = PaintingStyle.fill;
    Path path1 = Path(); Path path2 = Path(); Path path3 = Path();
    path1.moveTo(0, size.height); path2.moveTo(0, size.height); path3.moveTo(0, size.height);
    for (double i = 0; i <= size.width; i++) {
      double y1 = math.sin((i / size.width * 2 * math.pi) + phase) * 15 + targetHeight;
      double y2 = math.cos((i / size.width * 2 * math.pi) + phase * 1.5) * 20 + targetHeight + 10;
      double y3 = math.sin((i / size.width * 2 * math.pi) - phase * 1.2) * 12 + targetHeight + 20; 
      path1.lineTo(i, y1); path2.lineTo(i, y2); path3.lineTo(i, y3);
    }
    path1.lineTo(size.width, size.height); path1.close(); path2.lineTo(size.width, size.height); path2.close(); path3.lineTo(size.width, size.height); path3.close();
    canvas.drawPath(path1, wave1); canvas.drawPath(path2, wave2); canvas.drawPath(path3, wave3);
  }
  @override bool shouldRepaint(covariant AmbientWavePainter oldDelegate) => true;
}

class GoldenParticlePainter extends CustomPainter {
  final double time;
  GoldenParticlePainter({required this.time});
  @override
  void paint(Canvas canvas, Size size) {
    Paint particlePaint = Paint()..color = const Color(0xFFD4AF37).withOpacity(0.4)..style = PaintingStyle.fill..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);
    for (int i = 0; i < 25; i++) {
      double xOffset = (math.sin(time + i) * 50) + (size.width / 25 * i);
      double yOffset = size.height - ((time * 100 + (i * 40)) % size.height);
      double pSize = (math.sin(time * 2 + i) + 2) * 1.5; 
      canvas.drawCircle(Offset(xOffset, yOffset), pSize, particlePaint);
    }
  }
  @override bool shouldRepaint(covariant GoldenParticlePainter oldDelegate) => true;
}