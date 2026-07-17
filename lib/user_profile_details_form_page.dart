import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'main.dart';
import 'app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfileDetailsFormPage extends StatefulWidget {
  final UserData userData;
  const UserProfileDetailsFormPage({super.key, required this.userData});

  @override
  State<UserProfileDetailsFormPage> createState() => _UserProfileDetailsFormPageState();
}

class _UserProfileDetailsFormPageState extends State<UserProfileDetailsFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _phoneCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _linkedinCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();

  String? _selectedYear;
  bool _isSaving = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _dobCtrl.dispose();
    _linkedinCtrl.dispose();
    _deptCtrl.dispose();
    _yearCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2004, 1, 1),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4DA6FF),
              onPrimary: Colors.black,
              surface: Color(0xFF13223F),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF0D1B2A),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _dobCtrl.text =
            "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  Future<void> _saveDetails() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final res = await http.post(
        Uri.parse('$apiBaseUrl/api/user/details'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': widget.userData.email,
          'roll_number': widget.userData.rollNumber,
          'name': widget.userData.name,
          'phone_number': _phoneCtrl.text.trim(),
          'dob': _dobCtrl.text.trim(),
          'linkedin_url': _linkedinCtrl.text.trim(),
          'department': _deptCtrl.text.trim(),
          'year_of_study': _yearCtrl.text.trim(),
          'summary': _summaryCtrl.text.trim(),
        }),
      );

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('profile_completed_${widget.userData.email}', true);
        } catch (e) {
          debugPrint('SharedPreferences write error: $e');
        }
        if (mounted) {
          AppToast.success(context, 'Profile details saved successfully!');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => MainPage(userData: widget.userData),
            ),
          );
        }
      } else {
        if (mounted) {
          AppToast.error(context, data['message'] ?? 'Failed to save details.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.error(context, 'Error saving profile: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    VoidCallback? onTap,
    int maxLines = 1,
    String? hintText,
  }) {
    final poppins = GoogleFonts.poppins;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: poppins(color: const Color(0xFF8A9CC2), fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          onTap: onTap,
          maxLines: maxLines,
          style: poppins(color: readOnly ? Colors.white54 : Colors.white, fontSize: 14),
          validator: validator,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: poppins(color: Colors.white24, fontSize: 13),
            prefixIcon: Icon(icon, color: const Color(0xFF4DA6FF), size: 18),
            filled: true,
            fillColor: readOnly
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.white.withValues(alpha: 0.05),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    final nameCtrl = TextEditingController(text: widget.userData.name);
    final rollCtrl = TextEditingController(text: widget.userData.rollNumber);
    final emailCtrl = TextEditingController(text: widget.userData.email);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            top: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00C48C).withValues(alpha: 0.1),
                    blurRadius: 120,
                    spreadRadius: 60,
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Form(
                    key: _formKey,
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF4DA6FF).withValues(alpha: 0.12),
                          border: Border.all(
                              color: const Color(0xFF4DA6FF).withValues(alpha: 0.25),
                              width: 1),
                        ),
                        child: const Icon(
                          Icons.assignment_ind_rounded,
                          size: 40,
                          color: Color(0xFF4DA6FF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        'Complete Your Profile',
                        style: poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Fill in your details to enter the portal',
                        style: poppins(fontSize: 13, color: const Color(0xFF8A9CC2)),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Pre-filled section
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: Column(
                        children: [
                          _buildTextField(
                            label: 'Full Name',
                            controller: nameCtrl,
                            icon: Icons.person_rounded,
                            readOnly: true,
                          ),
                          _buildTextField(
                            label: 'Roll Number',
                            controller: rollCtrl,
                            icon: Icons.badge_rounded,
                            readOnly: true,
                          ),
                          _buildTextField(
                            label: 'Email ID',
                            controller: emailCtrl,
                            icon: Icons.email_rounded,
                            readOnly: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Text(
                      'Personal & Academic Details',
                      style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                    ),
                    const Divider(color: Colors.white10, height: 20),

                    _buildTextField(
                      label: 'Phone Number',
                      controller: _phoneCtrl,
                      icon: Icons.phone_rounded,
                      keyboardType: TextInputType.phone,
                      hintText: 'e.g. 9876543210',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Phone number is required';
                        if (v.trim().length < 10) return 'Enter a valid phone number';
                        return null;
                      },
                    ),

                    _buildTextField(
                      label: 'Date of Birth',
                      controller: _dobCtrl,
                      icon: Icons.calendar_today_rounded,
                      readOnly: true,
                      onTap: _selectDate,
                      hintText: 'Tap to select',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Date of birth is required';
                        return null;
                      },
                    ),

                    // Year of Study Dropdown
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Year of Study',
                          style: poppins(color: const Color(0xFF8A9CC2), fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedYear,
                          dropdownColor: const Color(0xFF0D1B2A),
                          style: poppins(color: Colors.white, fontSize: 14),
                          validator: (value) => value == null ? 'Please select your year of study' : null,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.school_rounded, color: Color(0xFF4DA6FF), size: 18),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF4DA6FF), width: 1.5),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFFF6B6B)),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          items: const [
                            DropdownMenuItem(value: '1st Year', child: Text('1st Year')),
                            DropdownMenuItem(value: '2nd Year', child: Text('2nd Year')),
                            DropdownMenuItem(value: '3rd Year', child: Text('3rd Year')),
                            DropdownMenuItem(value: 'Final Year', child: Text('Final Year')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              _selectedYear = val;
                              _yearCtrl.text = val ?? '';
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                    _buildTextField(
                      label: 'Department',
                      controller: _deptCtrl,
                      icon: Icons.lan_rounded,
                      hintText: 'e.g. Computer Science and Engineering',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Department is required';
                        return null;
                      },
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'Online Presence',
                      style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                    ),
                    const Divider(color: Colors.white10, height: 20),

                    _buildTextField(
                      label: 'LinkedIn Profile URL',
                      controller: _linkedinCtrl,
                      icon: Icons.link_rounded,
                      keyboardType: TextInputType.url,
                      hintText: 'https://linkedin.com/in/yourname',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'LinkedIn URL is required';
                        if (!v.trim().contains('linkedin.com')) return 'Enter a valid LinkedIn URL';
                        return null;
                      },
                    ),

                    const SizedBox(height: 4),

                    Text(
                      'About Yourself',
                      style: poppins(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF4DA6FF)),
                    ),
                    const Divider(color: Colors.white10, height: 20),

                    _buildTextField(
                      label: 'Summary',
                      controller: _summaryCtrl,
                      icon: Icons.description_rounded,
                      maxLines: 5,
                      hintText: 'Write a brief introduction — your interests, skills, goals and what you bring to SEDS...',
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Summary is required';
                        final wordCount = v.trim().split(RegExp(r'\s+')).length;
                        if (wordCount < 20) return 'Summary must be at least 20 words ($wordCount/20)';
                        return null;
                      },
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4DA6FF),
                          foregroundColor: Colors.black,
                          elevation: 4,
                          shadowColor: const Color(0xFF4DA6FF).withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: _isSaving ? null : _saveDetails,
                        child: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.black),
                              )
                            : Text(
                                'Save & Enter Portal',
                                style: poppins(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}
