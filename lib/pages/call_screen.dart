import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:link_up/providers/call_providers.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/styles/styles.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String calleeId;
  final String calleeName;
  final String calleeProfilePicture;
  final bool isVideo;
  final bool isCaller;
  final String? callId; // Only set when joining an existing call (callee)
  final String? remoteOffer; // Only set for callee

  const CallScreen({
    super.key,
    required this.calleeId,
    required this.calleeName,
    required this.calleeProfilePicture,
    required this.isVideo,
    required this.isCaller,
    this.callId,
    this.remoteOffer,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  // ─── WebRTC ───
  RTCPeerConnection? _peerConnection; // instance used to establish connection
  final RTCVideoRenderer _localRenderer =
      RTCVideoRenderer(); // instance used to render video of the current user
  final RTCVideoRenderer _remoteRenderer =
      RTCVideoRenderer(); // instance used to render video of the remote user
  MediaStream?
  _localStream; // instance used to extract the voice & media related details of current user

  // ─── Subscriptions ───
  StreamSubscription? _callSub; // call subscription
  StreamSubscription? _iceSub; // ice candidate subscription

  // ignore: prefer_final_fields
  String? callId;
  bool _isSpeaker = false;
  bool _isHangingUp = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  // ─── Current User ───
  String get _currentUserId => FirebaseAuth.instance.currentUser!.uid;
  String get _currentUserName =>
      FirebaseAuth.instance.currentUser!.displayName ?? 'Unknown';

  // ─── ICE Servers (free STUN servers from Google) ───
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _sendCandidate(RTCIceCandidate candidate) async {
    try {
      // ice candidates created by caller and added to appwrite
      await CallService.addIceCandidate(
        callId: callId!,
        senderId: _currentUserId,
        candidate: jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    } catch (e) {
      log('[ICE] Send failed: $e');
    }
  }

  Future<void> _initCall() async {
    // 1. Init renderers
    try {
      if (!mounted) return;
      await _localRenderer.initialize();
      if (!mounted) return;
      await _remoteRenderer.initialize();
    } catch (e) {
      _showError('Failed to initialize video. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 2. Get local media (camera + microphone)
    try {
      if (!mounted) return;
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo
            ? {'facingMode': 'user', 'width': 640, 'height': 480}
            : false,
      });
      // ✅ DEBUG HERE — tracks exist now
      for (final t in _localStream!.getTracks()) {
        log("LOCAL TRACK → ${t.kind} enabled=${t.enabled}");
      }
      log("VIDEO TRACK COUNT → ${_localStream!.getVideoTracks().length}");
      if (!mounted) return;
      _localRenderer.srcObject = _localStream;
    } catch (e) {
      _showError(
        'Could not access your ${widget.isVideo ? 'camera and microphone' : 'microphone'}. '
        'Please check your permissions and try again.',
      );
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 3. Create RTCPeerConnection
    try {
      if (!mounted) return;
      _peerConnection = await createPeerConnection(_iceServers);
      _peerConnection!.onConnectionState = (state) async {
        log("PC CONNECTION STATE → $state");
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          await Helper.setSpeakerphoneOn(true);
          log("SPEAKER ENABLED AFTER CONNECT");
        }
      };
      // 4. Listen for ICE candidates and send them to Appwrite
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) return;

        if (callId == null) {
          _pendingCandidates.add(candidate);
        } else {
          _sendCandidate(candidate);
        }
      };
    } catch (e) {
      _showError('Failed to establish connection. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 5. Add local tracks to the peer connection
    for (final track in _localStream!.getTracks()) {
      try {
        if (!mounted) return;
        await _peerConnection!.addTrack(track, _localStream!);
        log("TRACK ADDED TO PC → ${track.kind}");
      } catch (e) {
        _showError('Failed to set up media tracks. Please try again.');
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
    }

    // 6. Listen for remote tracks
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isEmpty) return;

      final stream = event.streams[0];

      // ── DEBUG LOG ──
      log(
        "Remote stream tracks: video=${stream.getVideoTracks().length}, audio=${stream.getAudioTracks().length}",
      );

      if (stream.getVideoTracks().isNotEmpty) {
        _remoteRenderer.srcObject = stream;
        log("VIDEO STREAM ATTACHED TO RENDERER");
      }

      if (mounted) {
        setState(() {});
        ref.read(callProvider.notifier).isConnected = true;
      }
    };
    // 7. Handle ICE connection state changes
    _peerConnection!
        .onIceConnectionState = (RTCIceConnectionState state) async {
      log("ICE STATE → $state");

      // ✅ When connection is established → enable audio output
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        await Helper.setSpeakerphoneOn(true);
        log("SPEAKER FORCED ON");
      }

      // ❌ When connection fails → hang up
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (mounted) {
          _hangUp();
        }
      }
    };

    if (widget.isCaller) {
      await _startCall();
    } else {
      await _joinCall();
    }
  }

  Future<void> _startCall() async {
    try {
      // Create SDP offer
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideo,
      });
      if (!mounted) return;

      await _peerConnection!.setLocalDescription(offer);
      if (!mounted) return;

      // Creating SDP offer and adding that offer to appwrite
      final doc = await CallService.createCall(
        callerId: _currentUserId,
        callerName: _currentUserName,
        calleeId: widget.calleeId,
        offer: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
        isVideo: widget.isVideo,
      );
      if (!mounted) return;

      if (doc == null) {
        _showError('Failed to start the call. Please try again.');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      callId = doc.$id;
      for (final c in _pendingCandidates) {
        _sendCandidate(c);
      }
      _pendingCandidates.clear();
    } catch (e) {
      _showError('Failed to start the call. Please try again.');
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // subscribing to call changes checking whether the calle has answered or not
    _callSub = CallService.subscribeToCallChanges(callId!, (response) {
      try {
        final payload = response.payload;
        final status = payload['status'] as String?;

        if (status == 'answered') {
          // Callee answered → set remote description
          final answerData = jsonDecode(payload['answer'] as String);
          // sending sdp offer to callee through peer connection
          _peerConnection?.setRemoteDescription(
            RTCSessionDescription(answerData['sdp'], answerData['type']),
          );
        }
      } catch (e) {
        _showError('Connection issue. The call may drop.');
      }
    });

    // Subscribe to ICE candidates sended by the callee
    _iceSub = CallService.subscribeToIceCandidates(callId!, _currentUserId, (
      response,
    ) {
      try {
        final candidateData = jsonDecode(
          response.payload['candidate']
              as String, // extracting ice candidate sended by the callee
        );
        _peerConnection?.addCandidate(
          // adding ice candidate of callee to peer connection
          RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          ),
        );
      } catch (e) {
        log('Error adding remote candidate: $e');
      }
    });
  }

  Future<void> _joinCall() async {
    // Set the caller's offer as remote description
    try {
      // sdp offer of caller extracted from appwrite
      final offerData = jsonDecode(widget.remoteOffer!);

      // adding sdp offer of caller to peer connection
      if (!mounted) return;
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type']),
      );
    } catch (e) {
      _showError('Failed to connect to the call. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    try {
      // Create SDP answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideo,
      });
      if (!mounted) return;

      await _peerConnection!.setLocalDescription(answer);
      if (!mounted) return;

      // Send answer back to Appwrite
      await CallService.answerCall(
        callId: widget.callId!,
        // adding sdp answer of callee to appwrite
        answer: jsonEncode({'sdp': answer.sdp, 'type': answer.type}),
      );
      if (!mounted) return;
    } catch (e) {
      _showError('Failed to connect to the call. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Subscribe to call changes (detect "ended")
    _callSub = CallService.subscribeToCallChanges(widget.callId!, (response) {
      try {
        final status = response.payload['status'] as String?;

        if (status == 'ended') {
          _cleanupAndPop();
        }
      } catch (e) {
        log('Error in call changes subscription: $e');
      }
    });

    // Subscribe to ICE candidates
    _iceSub = CallService.subscribeToIceCandidates(
      widget.callId!,
      _currentUserId,
      (response) {
        try {
          final candidateData = jsonDecode(
            response.payload['candidate'] as String,
          );
          _peerConnection?.addCandidate(
            RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex'],
            ),
          );
        } catch (e) {
          log('Error adding remote candidate: $e');
        }
      },
    );
  }

  Future<void> _hangUp() async {
    if (_isHangingUp) return;
    _isHangingUp = true;
    if (!mounted) return;
    ref.read(loadingProvider.notifier).state = true;

    try {
      if (callId != null) {
        await CallService.endCall(callId!);
        await CallService.cleanupCall(callId!);
      } else {
        log('No call ID found');
      }
    } catch (e) {
      log('Error ending call: $e');
    } finally {
      _cleanupAndPop();
    }
  }

  void _cleanupAndPop() {
    if (!_isHangingUp) {
      _isHangingUp = true;
      if (!mounted) return;
      ref.read(loadingProvider.notifier).state = true;
    }

    try {
      _callSub?.cancel();
      _iceSub?.cancel();
      _localStream?.getTracks().forEach((track) => track.stop());
      _localStream?.dispose();
      _peerConnection?.close();
      _peerConnection = null;
    } catch (e) {
      log('Error cleaning up call: $e');
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _toggleMute() {
    try {
      final audioTracks = _localStream?.getAudioTracks();
      if (audioTracks != null && audioTracks.isNotEmpty) {
        final enabled = !audioTracks[0].enabled;
        audioTracks[0].enabled = enabled;
        if (!mounted) return;
        ref.read(callProvider.notifier).isMuted = !enabled;
      }
    } catch (e) {
      _showError('Could not toggle mute. Please try again.');
    }
  }

  void _toggleSpeaker() async {
    try {
      _isSpeaker = !_isSpeaker;
      await Helper.setSpeakerphoneOn(_isSpeaker);

      if (!mounted) return;
      ref.read(callProvider.notifier).isSpeaker = _isSpeaker;
    } catch (e) {
      _showError('Could not toggle speaker. Please try again.');
    }
  }

  void _toggleCamera() {
    try {
      final videoTracks = _localStream?.getVideoTracks();
      if (videoTracks != null && videoTracks.isNotEmpty) {
        final enabled = !videoTracks[0].enabled;
        videoTracks[0].enabled = enabled;
        if (!mounted) return;
        ref.read(callProvider.notifier).isCameraOff = !enabled;
      }
    } catch (e) {
      _showError('Could not toggle camera. Please try again.');
    }
  }

  void _switchCamera() {
    try {
      final videoTracks = _localStream?.getVideoTracks();
      if (videoTracks != null && videoTracks.isNotEmpty) {
        Helper.switchCamera(videoTracks[0]);
      }
    } catch (e) {
      _showError('Could not switch camera. Please try again.');
    }
  }

  @override
  void dispose() {
    _callSub?.cancel();
    _iceSub?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Consumer(
          builder: (context, ref, child) {
            final isCameraOff = ref.watch(
              callProvider.select((state) => state.isCameraOff),
            );
            final isMuted = ref.watch(
              callProvider.select((state) => state.isMuted),
            );
            final isSpeaker = ref.watch(
              callProvider.select((state) => state.isSpeaker),
            );
            final isConnected = ref.watch(
              callProvider.select((state) => state.isConnected),
            );
            final isLoading = ref.watch(loadingProvider);

            return Stack(
              children: [
                // ── Remote Video (full screen) ──
                if (widget.isVideo && _remoteRenderer.srcObject != null)
                  Positioned.fill(
                    child: isConnected
                        ? RTCVideoView(
                            _remoteRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        : _buildWaitingUI(),
                  )
                else
                  Positioned.fill(child: _buildAudioCallUI()),

                // ── Local Video (small pip) ──
                if (widget.isVideo && !isCameraOff)
                  Positioned(
                    top: 20,
                    right: 20,
                    width: 120,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white30, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: RTCVideoView(
                          _localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),

                // ── Callee Info (top) ──
                if (!isConnected || !widget.isVideo)
                  Positioned(
                    top: 40,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: AppColors.primaryBlue.withOpacity(
                            0.3,
                          ),
                          backgroundImage:
                              widget.calleeProfilePicture.isNotEmpty
                              ? NetworkImage(widget.calleeProfilePicture)
                              : null,
                          child: widget.calleeProfilePicture.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.calleeName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),

                        Text(
                          isConnected
                              ? 'Connected'
                              : (widget.isCaller
                                    ? 'Calling...'
                                    : 'Connecting...'),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),

                // ── Control Buttons (bottom) ──
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Mute
                            _buildControlButton(
                              icon: isMuted ? Icons.mic_off : Icons.mic,
                              label: isMuted ? 'Unmute' : 'Mute',
                              onTap: _toggleMute,
                              isActive: isMuted,
                            ),

                            // Speaker
                            _buildControlButton(
                              icon: isSpeaker
                                  ? Icons.volume_up
                                  : Icons.volume_down,
                              label: 'Speaker',
                              onTap: _toggleSpeaker,
                              isActive: isSpeaker,
                            ),

                            // Camera toggle (only for video calls)
                            if (widget.isVideo)
                              _buildControlButton(
                                icon: isCameraOff
                                    ? Icons.videocam_off
                                    : Icons.videocam,
                                label: isCameraOff ? 'Camera On' : 'Camera Off',
                                onTap: _toggleCamera,
                                isActive: isCameraOff,
                              ),

                            // Switch camera (only for video calls)
                            if (widget.isVideo)
                              _buildControlButton(
                                icon: Icons.cameraswitch,
                                label: 'Flip',
                                onTap: _switchCamera,
                              ),

                            // Hang up
                            _buildControlButton(
                              icon: Icons.call_end,
                              label: 'End',
                              onTap: _hangUp,
                              color: Colors.red,
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── Waiting for connection UI ──
  Widget _buildWaitingUI() {
    return Container(
      color: const Color(0xFF1A1A2E),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primaryBlue),
            SizedBox(height: 16),
            Text(
              'Waiting for connection...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ── Audio-only call UI ──
  Widget _buildAudioCallUI() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
    );
  }

  // ── Reusable control button ──
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color:
                  color ??
                  (isActive
                      ? Colors.white.withOpacity(0.3)
                      : Colors.white.withOpacity(0.1)),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
