import 'package:flutter/material.dart';
import 'package:link_up/pages/call_screen.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/styles/styles.dart';

class IncomingCallScreen extends StatelessWidget {
  final String callId;
  final String callerName;
  final String callerId;
  final String offer; // JSON-encoded SDP offer from caller
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callerId,
    required this.offer,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),
            // ── Caller Avatar ──
            CircleAvatar(
              radius: 60,
              backgroundColor: AppColors.primaryBlue.withOpacity(0.3),
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),

            // ── Caller Name ──
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // ── Call Type Label ──
            Text(
              isVideo ? 'Incoming Video Call...' : 'Incoming Audio Call...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 18,
              ),
            ),

            const Spacer(flex: 3),

            // ── Accept / Reject Buttons ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject
                  _buildActionButton(
                    icon: Icons.call_end,
                    label: 'Reject',
                    color: Colors.red,
                    onTap: () async {
                      await CallService.endCall(callId);
                      if (context.mounted && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),

                  // Accept
                  _buildActionButton(
                    icon: isVideo ? Icons.videocam : Icons.call,
                    label: 'Accept',
                    color: Colors.green,
                    onTap: () {
                      // Navigate to CallScreen as callee
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => CallScreen(
                            calleeId: callerId,
                            calleeName: callerName,
                            calleeProfilePicture: '',
                            isVideo: isVideo,
                            isCaller: false,
                            callId: callId,
                            remoteOffer: offer,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
