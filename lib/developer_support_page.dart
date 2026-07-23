import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'app_toast.dart';

class DeveloperSupportPage extends StatelessWidget {
  const DeveloperSupportPage({super.key});

  Future<void> _launchUrl(BuildContext context, String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        if (context.mounted) {
          AppToast.error(context, 'Could not launch link.');
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Error launching link. App might be missing.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final poppins = GoogleFonts.poppins;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1E3A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Developer & Support',
          style: poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  Container(color: const Color(0xFF0D1E3A)),
            ),
          ),
          Positioned.fill(
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),
              // Builder Profile Header
              Text(
                'BUILDER PROFILE',
                style: poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: const Color(0xFF4DA6FF),
                ),
              ),
              const SizedBox(height: 16),

              // Developer Profile Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.08),
                      Colors.white.withValues(alpha: 0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Developer Image
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4DA6FF).withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: const Color(0xFF4DA6FF),
                          width: 3.0,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.network(
                          'https://kumaraguruseds.space/mani.jpeg',
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF4DA6FF),
                              ),
                            );
                          },
                          errorBuilder: (ctx, err, st) => Container(
                            color: const Color(0xFF1B2E4F),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 60,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Developer Name
                    Text(
                      'Manikandan N',
                      style: poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Developer Tagline
                    Text(
                      'Full Stack Web Developer & Flutter App Developer\nAI/ML Engineer',
                      style: poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF00E5FF),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    // Department
                    Text(
                      'Aeronautical Department',
                      style: poppins(
                        fontSize: 13,
                        color: const Color(0xFF8A9CC2),
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Divider
                    Container(
                      height: 1,
                      width: 100,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    const SizedBox(height: 24),

                    // Contact Info Details
                    _infoDetailTile(
                      poppins: poppins,
                      icon: Icons.phone_rounded,
                      label: 'Contact Number',
                      value: '+91 9344752075',
                      onTap: () => _launchUrl(context, 'tel:9344752075'),
                    ),
                    const SizedBox(height: 16),
                    _infoDetailTile(
                      poppins: poppins,
                      icon: Icons.email_rounded,
                      label: 'Email Address',
                      value: 'manilunar07@gmail.com',
                      onTap: () => _launchUrl(context, 'mailto:manilunar07@gmail.com'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Contact & Support Options Header
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Text(
                    'GET IN TOUCH',
                    style: poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: const Color(0xFF4DA6FF),
                    ),
                  ),
                ),
              ),

              // Quick Connect Actions
              _buildSupportActionTile(
                poppins: poppins,
                icon: Icons.chat_rounded,
                title: 'WhatsApp Chat',
                subtitle: 'Send a quick message on WhatsApp',
                color: const Color(0xFF00C48C),
                onTap: () => _launchUrl(context, 'https://wa.me/919344752075'),
              ),
              const SizedBox(height: 12),
              _buildSupportActionTile(
                poppins: poppins,
                icon: Icons.mail_outline_rounded,
                title: 'Email Support',
                subtitle: 'Send details or screenshots via email',
                color: const Color(0xFF9B59B6),
                onTap: () => _launchUrl(context, 'mailto:manilunar07@gmail.com?subject=SEDS%20Portal%20Feedback%20/%20Support'),
              ),
              const SizedBox(height: 12),
              _buildSupportActionTile(
                poppins: poppins,
                icon: Icons.phone_in_talk_rounded,
                title: 'Call Developer',
                subtitle: 'Direct telephonic support call',
                color: const Color(0xFFFF9F43),
                onTap: () => _launchUrl(context, 'tel:9344752075'),
              ),

               const SizedBox(height: 32),
               // App version footer
               FutureBuilder<PackageInfo>(
                 future: PackageInfo.fromPlatform(),
                 builder: (context, snapshot) {
                   final String version = snapshot.hasData
                       ? 'SEDS Portal App • Version ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                       : 'SEDS Portal App • Version 1.0.7';
                   return Text(
                     version,
                     style: poppins(
                       fontSize: 11,
                       color: Colors.white30,
                       fontWeight: FontWeight.w500,
                     ),
                   );
                 },
               ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
        ],
      ),
    );
  }

  Widget _infoDetailTile({
    required TextStyle Function({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    }) poppins,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF4DA6FF).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: const Color(0xFF4DA6FF), size: 18),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: poppins(
                      fontSize: 11,
                      color: const Color(0xFF8A9CC2),
                    ),
                  ),
                  Text(
                    value,
                    style: poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              color: Colors.white30,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportActionTile({
    required TextStyle Function({
      Color? color,
      double? fontSize,
      FontWeight? fontWeight,
      double? letterSpacing,
    }) poppins,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: poppins(
                          fontSize: 11,
                          color: const Color(0xFF8A9CC2),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: Colors.white30,
                  size: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
