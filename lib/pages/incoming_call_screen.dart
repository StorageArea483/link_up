import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:link_up/pages/call_screen.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class IncomingCallScreen extends StatefulWidget {
  final String callId;
  final String callerName;
  final String callerPhoneNumber;
  final String callerProfilePicture;
  final String callerId;
  final String offer;
  final bool isVideo;

  const IncomingCallScreen({
    super.key,
    required this.callId,
    required this.callerName,
    required this.callerPhoneNumber,
    required this.callerProfilePicture,
    required this.callerId,
    required this.offer,
    required this.isVideo,
  });

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen> {
  // ── Show callkit notification + start ringing ──
  Future<void> _showIncomingCallNotification() async {
    final params = CallKitParams(
      id: widget.callId, // use real callId instead of hardcoded string
      nameCaller: widget.callerName,
      appName: 'LinkUp',
      handle: widget.callerPhoneNumber,
      type: widget.isVideo ? 1 : 0, // 0 = audio, 1 = video
      duration: 30000,
      android: const AndroidParams(
        isCustomNotification: true,
        isShowFullLockedScreen: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#1A1A2E',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  // ── Listen to callkit events (accept/decline from notification) ──
  void _listenToCallEvents() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (!mounted) return;

      switch (event!.event) {
        case Event.actionCallAccept:
          await _handleAccept();
          break;

        case Event.actionCallDecline:
          await _handleReject();
          break;

        case Event.actionCallEnded:
        case Event.actionCallTimeout:
          await CallService.endCall(widget.callId);
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
          break;

        // safely ignore unneeded events
        default:
          break;
      }
    });
  }

  // ── Accept logic ──
  Future<void> _handleAccept() async {
    final isActive = await CallService.isCallActive(widget.callId);
    if (!isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call ended.'),
            backgroundColor: Colors.red,
          ),
        );
        if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => CheckConnection(
            child: CallScreen(
              calleeId: widget.callerId,
              calleeName: widget.callerName,
              callerProfilePicture: widget.callerProfilePicture,
              isVideo: widget.isVideo,
              isCaller: false,
              callId: widget.callId,
              remoteOffer: widget.offer,
            ),
          ),
        ),
      );
    }
  }

  // ── Reject logic ──
  Future<void> _handleReject() async {
    await FlutterCallkitIncoming.endCall(widget.callId);
    await CallService.endCall(widget.callId);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showIncomingCallNotification(); // show notification + ring
      _listenToCallEvents(); // listen for accept/decline
    });
  }

  @override
  void dispose() {
    // End callkit UI if screen is disposed (e.g. caller hung up)
    FlutterCallkitIncoming.endCall(widget.callId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 2),

            CircleAvatar(
              radius: 60,
              backgroundColor: AppColors.primaryBlue.withOpacity(0.3),
              child: const Icon(Icons.person, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 24),

            Text(
              widget.callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Text(
              widget.isVideo
                  ? 'Incoming Video Call...'
                  : 'Incoming Audio Call...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 18,
              ),
            ),

            const Spacer(flex: 3),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // ── Reject Button ──
                  _buildActionButton(
                    icon: Icons.call_end,
                    label: 'Reject',
                    color: Colors.red,
                    onTap: _handleReject, // 👈 centralized logic
                  ),

                  // ── Accept Button ──
                  _buildActionButton(
                    icon: widget.isVideo ? Icons.videocam : Icons.call,
                    label: 'Accept',
                    color: Colors.green,
                    onTap: _handleAccept, // 👈 centralized logic
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
