// =============================================================================
// Forgot Password Screen — Send Firebase password reset email
// =============================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();

  bool _isLoading = false;
  bool _emailSent = false;
  String? _errorMessage;
  String? _resolvedEmail;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = await AuthService.sendPasswordReset(
        doctorId: _idController.text,
      );
      setState(() {
        _isLoading = false;
        _emailSent = true;
        _resolvedEmail = email;
      });
    } on FirebaseAuthException catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = AuthService.friendlyError(e);
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Reset Password',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: _emailSent ? _buildSuccessCard() : _buildFormCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Semantics(
      container: true,
      label: 'Password reset form',
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.softShadow,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Forgot your password?',
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your Staff ID or email. We will send a reset link to the registered address.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                label: 'Staff ID or email for password reset',
                child: TextFormField(
                  controller: _idController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _sendReset(),
                  decoration: const InputDecoration(
                    hintText: 'Staff ID or Email',
                    prefixIcon: Icon(Icons.badge_outlined),
                    prefixIconColor: AppTheme.primaryBlue,
                    suffixText: '@moh.om',
                    suffixStyle: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your Staff ID or email';
                    }
                    return null;
                  },
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppTheme.dangerRed,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Semantics(
                button: true,
                label: 'Send password reset email',
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sendReset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            'Send Reset Link',
                            style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Semantics(
      liveRegion: true,
      label: 'Password reset email sent',
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.softShadow,
        ),
        child: Column(
          children: [
            const Icon(Icons.mark_email_read_rounded,
                size: 64, color: AppTheme.successGreen),
            const SizedBox(height: 20),
            Text(
              'Check your inbox',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'A password reset link was sent to:\n$_resolvedEmail',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Back to Sign In'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
