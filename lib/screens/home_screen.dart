// =============================================================================
// Home Screen — X-Ray Upload & Analysis
// =============================================================================
// Main screen with upload button, info cards, and medical disclaimer.
// Displays the signed-in doctor's name/email from FirebaseAuth.
// =============================================================================

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/classifier_service.dart';
import '../services/image_service.dart';
import '../services/image_validation.dart';
import '../services/auth_service.dart';
import '../widgets/custom_drawer.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  final String doctorName;
  final String doctorEmail;
  final String role;

  const HomeScreen({
    super.key,
    required this.doctorName,
    required this.doctorEmail,
    required this.role,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  final ClassifierService _classifier = ClassifierService.instance;
  final ImageService _imageService = ImageService();

  bool _isModelLoading = true;
  bool _isAnalyzing = false;
  bool _modelError = false;
  File? _selectedImage;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _initModel();
  }

  String _errorMessage = '';

  Future<void> _initModel() async {
    try {
      await _classifier.initialize();
      setState(() => _isModelLoading = false);
    } catch (e) {
      setState(() {
        _isModelLoading = false;
        _modelError = true;
        _errorMessage = e.toString();
      });
    }
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────────
  Future<void> _pickAndAnalyze() async {
    try {
      final image = await _imageService.pickFromGallery();
      if (image == null) return;

      setState(() {
        _selectedImage = image;
        _isAnalyzing = true;
      });

      final result = await _classifier.classify(image);

      // Save result to Firestore for Analytics & History
      await FirebaseFirestore.instance.collection('scans').add({
        'doctorName': widget.doctorName,
        'doctorEmail': widget.doctorEmail,
        'result': result.isPneumonia ? 'Pneumonia' : 'Normal',
        'confidence': result.confidence,
        'modelVersion': result.modelInfo?.version ?? '1.0.0',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _isAnalyzing = false);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ResultScreen(
              result: result,
              imageFile: image,
            ),
          ),
        );
      }
    } on ImagePickerException catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        _showError(e.message);
      }
    } on ImageValidationException catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        _showError(e.message);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAnalyzing = false);
        _showError('Analysis failed: ${e.toString()}');
      }
    }
  }

  Future<void> _logout() async {
    await AuthService.signOut();
    // AuthGate stream automatically returns to LoginScreen
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.dangerRed,
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('settings').doc('system').snapshots(),
      builder: (context, snapshot) {
        // Safe default: assume no maintenance if there's an error or it's loading
        bool isMaintenance = false;
        
        if (snapshot.hasError) {
          debugPrint("Maintenance Check Error: ${snapshot.error}");
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          isMaintenance = (snapshot.data!.data() as Map?)?['isMaintenance'] ?? false;
        }

        if (isMaintenance) {
          return _buildMaintenanceScreen();
        }

        return Scaffold(
          appBar: _isModelLoading || _modelError ? null : AppBar(
            title: Text(
              'OmniSense AI',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : Colors.white,
              ),
            ),
            actions: [
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('notifications').snapshots(),
                builder: (context, snapshot) {
                  final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.notifications_none_rounded),
                        onPressed: () => _showNotifications(),
                      ),
                      if (count > 0)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: AppTheme.dangerRed, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                            child: Text(
                              count > 9 ? '9+' : '$count',
                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          drawer: _isModelLoading || _modelError
              ? null
              : CustomDrawer(
                  doctorName: widget.doctorName,
                  doctorEmail: widget.doctorEmail,
                  role: widget.role,
                ),
          body: Container(
            decoration: BoxDecoration(
              gradient: Theme.of(context).brightness == Brightness.light
                  ? AppTheme.backgroundGradient
                  : AppTheme.darkBackgroundGradient,
            ),
            child: SafeArea(
              child: _isModelLoading
                  ? _buildLoadingState()
                  : _modelError
                      ? _buildErrorState()
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: _buildContent(),
                        ),
            ),
          ),
        );
      },
    );
  }

  void _showNotifications() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDarkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: isDark ? Colors.white24 : Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Row(
              children: [
                const Icon(Icons.notifications_active_rounded, color: AppTheme.primaryBlue),
                const SizedBox(width: 12),
                Text('System Notifications', 
                  style: GoogleFonts.poppins(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppTheme.textPrimary,
                  )
                ),
              ],
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text('No active notifications'),
                      ),
                    );
                  }
                  
                  final docs = snapshot.data!.docs;

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final type = data['type'] ?? 'Alert';
                      final isMaint = type == 'Maintenance';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isMaint 
                              ? AppTheme.warningAmber.withAlpha(isDark ? 30 : 15)
                              : (isDark ? Colors.white.withAlpha(10) : Colors.grey.shade50),
                          borderRadius: BorderRadius.circular(16),
                          border: isMaint ? Border.all(color: AppTheme.warningAmber.withAlpha(50)) : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(type.toUpperCase(), 
                                  style: GoogleFonts.inter(
                                    fontSize: 10, 
                                    fontWeight: FontWeight.w800, 
                                    color: isMaint ? AppTheme.warningAmber : AppTheme.primaryBlue,
                                    letterSpacing: 1,
                                  )
                                ),
                                Text(
                                  _formatTimestamp(data['timestamp']),
                                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              data['message'] ?? '',
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                color: isDark ? Colors.white : AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            )],
        ),
      ),
    );
  }

  Widget _buildMaintenanceScreen() {
    return Scaffold(
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.construction_rounded, size: 100, color: Colors.white),
            const SizedBox(height: 40),
            Text(
              'Under Maintenance',
              style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              'We are currently performing system updates to improve your experience. We will be back shortly.',
              style: GoogleFonts.inter(fontSize: 16, color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 50),
            ElevatedButton(
              onPressed: () => AuthService.signOut(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppTheme.primaryBlue,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading State ─────────────────────────────────────────────────────────────
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.medical_services_rounded,
                size: 40, color: Colors.white),
          ),
          const SizedBox(height: 28),
          const CircularProgressIndicator(color: AppTheme.primaryBlue),
          const SizedBox(height: 20),
          Text('Loading AI Model...',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // ── Error State ───────────────────────────────────────────────────────────────
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 64, color: AppTheme.dangerRed),
            const SizedBox(height: 20),
            Text('Model Loading Error',
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary)),
            const SizedBox(height: 12),
            Text(
              _errorMessage.isNotEmpty 
                  ? 'Error Details: $_errorMessage\n\nEnsure MULTI_OUTPUT_MODEL_flutter.tflite is in assets/model/ and pubspec.yaml is updated.'
                  : 'Could not load the AI model. Make sure MULTI_OUTPUT_MODEL_flutter.tflite exists in assets/model/',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isModelLoading = true;
                  _modelError = false;
                });
                _initModel();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main Content ──────────────────────────────────────────────────────────────
  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        _buildBroadcastAlert(), // Removed the SliverToBoxAdapter wrapper
        SliverToBoxAdapter(child: _buildUploadSection()),
        SliverToBoxAdapter(child: _buildInfoCards()),
        SliverToBoxAdapter(child: _buildDisclaimer()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  Widget _buildBroadcastAlert() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('broadcast')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SliverToBoxAdapter(child: SizedBox.shrink());

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final message = data['message'] as String;
        if (message.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());

        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          sliver: SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withAlpha(25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryBlue.withAlpha(50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.campaign_rounded, color: AppTheme.primaryBlue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SYSTEM ALERT',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryBlue,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          message,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    Color roleColor;
    switch (widget.role.toLowerCase()) {
      case 'radiologist': roleColor = Colors.purple; break;
      case 'technician': roleColor = Colors.orange; break;
      default: roleColor = AppTheme.primaryBlue;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome Back,',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary,
                  ),
                ),
                Text(
                  'Dr. ${widget.doctorName}',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: roleColor.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.verified_user_rounded,
                    size: 14, color: roleColor),
                const SizedBox(width: 4),
                Text(
                  widget.role.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: roleColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Upload Section ────────────────────────────────────────────────────────────
  Widget _buildUploadSection() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDarkCard : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: isDark ? null : AppTheme.softShadow,
          border: isDark ? Border.all(color: Colors.white.withAlpha(20)) : null,
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            ScaleTransition(
              scale: _pulseAnim,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_photo_alternate_rounded,
                  size: 48,
                  color: AppTheme.primaryBlue,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Upload Chest X-Ray',
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppTheme.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Select an X-ray image from your gallery\nfor AI-powered pneumonia analysis',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
                  height: 1.5),
            ),
            const SizedBox(height: 28),

            // Selected image preview
            if (_selectedImage != null && !_isAnalyzing)
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                height: 160,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: FileImage(_selectedImage!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            // Upload / Analyze button
            Semantics(
              button: true,
              label: _isAnalyzing
                  ? 'Analyzing chest X-ray'
                  : 'Upload and analyze chest X-ray',
              enabled: !_isAnalyzing,
              child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isAnalyzing ? null : _pickAndAnalyze,
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Icon(Icons.upload_rounded, size: 22),
                label: Text(
                  _isAnalyzing ? 'Analyzing...' : 'Upload & Analyze',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Info Cards ────────────────────────────────────────────────────────────────
  Widget _buildInfoCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How It Works',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary)),
          const SizedBox(height: 14),
          _infoCard(
            icon: Icons.image_outlined,
            title: 'Upload X-Ray',
            subtitle: 'Select a chest X-ray image from your gallery',
            color: AppTheme.primaryBlue,
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.psychology_outlined,
            title: 'AI Analysis',
            subtitle: 'AI model analyzes the image on-device',
            color: AppTheme.accentTeal,
          ),
          const SizedBox(height: 10),
          _infoCard(
            icon: Icons.assessment_outlined,
            title: 'View Results',
            subtitle: 'Get classification with confidence score',
            color: AppTheme.accentCyan,
          ),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: Theme.of(context).brightness == Brightness.light ? AppTheme.cardShadow : null,
        border: Theme.of(context).brightness == Brightness.dark ? Border.all(color: Colors.white.withAlpha(20)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).brightness == Brightness.light ? AppTheme.textPrimary : AppTheme.textDarkPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Disclaimer ────────────────────────────────────────────────────────────────
  Widget _buildDisclaimer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.warningAmber.withAlpha(15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.warningAmber.withAlpha(50)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 22, color: AppTheme.warningAmber.withAlpha(200)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This system is for educational and support purposes only. '
                'It is not a substitute for professional medical diagnosis. '
                'Always consult a qualified healthcare provider.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.light ? AppTheme.textSecondary : AppTheme.textDarkSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Now';
    final DateTime dt = (timestamp as Timestamp).toDate();
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return "${dt.day}/${dt.month}";
    }
  }
}
