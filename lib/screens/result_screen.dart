// =============================================================================
// Result Screen — Classification Results
// =============================================================================
// Displays the prediction result with an animated circular confidence
// indicator, color-coded label, analysis details, and medical disclaimer.
// =============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/classification_result.dart';

class ResultScreen extends StatefulWidget {
  final ClassificationResult result;
  final File imageFile;

  const ResultScreen({
    super.key,
    required this.result,
    required this.imageFile,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _ringController;
  late Animation<double> _ringAnim;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late AnimationController _slideController;
  late Animation<Offset> _slideAnim;
  bool _showHeatmap = false;

  @override
  void initState() {
    super.initState();

    // Confidence ring fill animation
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _ringAnim = Tween<double>(begin: 0, end: widget.result.confidence).animate(
      CurvedAnimation(parent: _ringController, curve: Curves.easeOutCubic),
    );

    // Fade-in animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    // Slide-up animation for cards
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );

    // Start animations sequentially
    _fadeController.forward();
    Future.delayed(const Duration(milliseconds: 200), () {
      _ringController.forward();
      _slideController.forward();
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  Color get _resultColor =>
      widget.result.isPneumonia ? AppTheme.dangerRed : AppTheme.successGreen;

  LinearGradient get _resultGradient => widget.result.isPneumonia
      ? AppTheme.pneumoniaGradient
      : AppTheme.normalGradient;

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkBackgroundGradient : AppTheme.backgroundGradient,
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildAppBar()),
                SliverToBoxAdapter(child: _buildResultHeader()),
                SliverToBoxAdapter(
                  child: SlideTransition(
                    position: _slideAnim,
                    child: Column(
                      children: [
                        _buildImagePreview(),
                        _buildAnalysisDetails(),
                        _buildDisclaimer(),
                        _buildActionButtons(),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── App Bar ─────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_ios_rounded),
            style: IconButton.styleFrom(
              backgroundColor: isDark ? AppTheme.surfaceDarkCard : Colors.white,
              foregroundColor: isDark ? Colors.white : AppTheme.textPrimary,
            ),
          ),
          const Spacer(),
          Text('Analysis Result',
              style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.textPrimary)),
          const Spacer(),
          const SizedBox(width: 48), // Balance
        ],
      ),
    );
  }

  // ── Result Header with Confidence Ring ──────────────────────────────────
  Widget _buildResultHeader() {
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
            // Animated confidence ring
            AnimatedBuilder(
              animation: _ringAnim,
              builder: (context, child) {
                return SizedBox(
                  width: 160,
                  height: 160,
                  child: CustomPaint(
                    painter: _ConfidenceRingPainter(
                      progress: _ringAnim.value,
                      color: _resultColor,
                      backgroundColor: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(_ringAnim.value * 100).toStringAsFixed(1)}%',
                            style: GoogleFonts.poppins(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: _resultColor,
                            ),
                          ),
                          Text(
                            'confidence',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? AppTheme.textDarkSecondary : AppTheme.textLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),

            // Classification label
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                gradient: _resultGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: _resultColor.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.result.isPneumonia
                        ? Icons.warning_rounded
                        : Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.result.label,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.result.isPneumonia
                  ? 'Signs of pneumonia detected in the X-ray'
                  : 'No signs of pneumonia detected',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Image & Heatmap Preview ──────────────────────────────────────────────
  Widget _buildImagePreview() {
    final hasHeatmap = widget.result.heatmapImage != null;

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDarkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark ? null : AppTheme.cardShadow,
          border: isDark ? Border.all(color: Colors.white.withAlpha(20)) : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _showHeatmap ? 'Grad-CAM Analysis' : 'Analyzed Image',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      _showHeatmap ? 'AI FOCUS REGIONS' : 'ORIGINAL X-RAY',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: (isDark ? AppTheme.primaryDarkBlue : AppTheme.primaryBlue).withAlpha(180),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                if (hasHeatmap)
                  Container(
                    height: 36,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(10) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: (isDark ? AppTheme.primaryDarkBlue : AppTheme.primaryBlue).withAlpha(isDark ? 80 : 40)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Row(
                      children: [
                        _toggleButton('Original', !_showHeatmap),
                        _toggleButton('Grad-CAM', _showHeatmap),
                      ],
                    ),
                  )
                else
                  _buildMissingGradCamInfo(),
              ],
            ),
            const SizedBox(height: 12),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: _showHeatmap && hasHeatmap
                        ? Image.memory(
                            widget.result.heatmapImage!,
                            key: const ValueKey('heatmap'),
                            width: double.infinity,
                            height: 240,
                            fit: BoxFit.cover,
                          )
                        : Image.file(
                            widget.imageFile,
                            key: const ValueKey('original'),
                            width: double.infinity,
                            height: 240,
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
                if (_showHeatmap && hasHeatmap)
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(150),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: const LinearGradient(
                                colors: [Colors.blue, Colors.green, Colors.red],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'High Focus',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (_showHeatmap && hasHeatmap) ...[
              const SizedBox(height: 16),
              Text(
                'The heatmap highlights regions (in red) where the AI detected features characteristic of pneumonia.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _toggleButton(String label, bool isSelected) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => setState(() => _showHeatmap = (label == 'Grad-CAM')),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? (isDark ? AppTheme.primaryDarkBlue : AppTheme.primaryBlue) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? AppTheme.textDarkSecondary : AppTheme.textLight),
          ),
        ),
      ),
    );
  }

  Widget _buildMissingGradCamInfo() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: isDark ? Colors.white38 : Colors.grey.shade400),
          const SizedBox(width: 6),
          Text(
            'Grad-CAM unavailable',
            style: GoogleFonts.inter(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.grey.shade500,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisDetails() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDarkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: isDark ? null : AppTheme.cardShadow,
          border: isDark ? Border.all(color: Colors.white.withAlpha(20)) : null,
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Analysis Details',
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppTheme.textPrimary)),
            const SizedBox(height: 16),
            _detailRow(Icons.timer_outlined, 'Inference Time',
                '${widget.result.inferenceTimeMs} ms'),
            const Divider(height: 20),
            _detailRow(Icons.devices_rounded, 'Processing',
                'On-device inference'),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color blueAccent = isDark ? AppTheme.primaryDarkBlue : AppTheme.primaryBlue;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: blueAccent.withAlpha(isDark ? 30 : 15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: blueAccent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(label,
              style: GoogleFonts.inter(
                  fontSize: 14, color: isDark ? AppTheme.textDarkSecondary : AppTheme.textSecondary)),
        ),
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppTheme.textPrimary)),
      ],
    );
  }

  // ── Disclaimer ──────────────────────────────────────────────────────────
  Widget _buildDisclaimer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
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
            Icon(Icons.info_outline_rounded,
                size: 20, color: AppTheme.warningAmber.withAlpha(200)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'This system is for educational and support purposes only. '
                'It is not a substitute for professional medical diagnosis.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Theme.of(context).brightness == Brightness.dark ? AppTheme.textDarkSecondary : AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Action Buttons ──────────────────────────────────────────────────────
  Widget _buildActionButtons() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color buttonColor = isDark ? AppTheme.primaryDarkBlue : AppTheme.primaryBlue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.add_photo_alternate_rounded),
              label: const Text('New Scan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor.withAlpha(isDark ? 40 : 15),
                foregroundColor: isDark ? Colors.white : buttonColor,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: isDark ? BorderSide(color: buttonColor.withAlpha(80)) : BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                // Implement Save
              },
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Save Result'),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Confidence Ring Painter — Custom circular progress indicator
// =============================================================================
class _ConfidenceRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _ConfidenceRingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    const strokeWidth = 10.0;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    // Progress ring
    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ConfidenceRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}
