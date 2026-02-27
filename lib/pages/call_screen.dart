import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:link_up/providers/call_providers.dart';
import 'package:link_up/providers/navigation_provider.dart';
import 'package:link_up/services/call_service.dart';
import 'package:link_up/styles/styles.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String calleeId;
  final String calleeName;
  final String callerProfilePicture;
  final bool isVideo;
  final bool isCaller;
  final String? callId;
  final String? remoteOffer;
  final bool? isOnline;

  const CallScreen({
    super.key,
    required this.calleeId,
    required this.calleeName,
    required this.callerProfilePicture,
    required this.isVideo,
    required this.isCaller,
    this.callId,
    this.remoteOffer,
    this.isOnline,
  });

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  // ─── WebRTC ───
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  MediaStream? _localStream;

  // ─── Subscriptions ───
  StreamSubscription? _callSub;
  StreamSubscription? _iceSub;

  // ─── State ───
  String? _callId;
  String get _resolvedCallId => _callId ?? widget.callId ?? '';

  bool _isSpeaker = false;
  bool _isHangingUp = false;
  bool _remoteDescSet = false;
  int _iceFailureCount = 0;
  final Set<String> _remoteCandidateSet = <String>{};

  // ─── Call Duration Timer ───
  Timer? _callDurationTimer;
  final List<Map<String, dynamic>> _pendingRemoteCandidates = [];

  // ─── Current User ───
  String get _currentUserId => FirebaseAuth.instance.currentUser!.uid;

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.relay.metered.ca:80'},
      // ─── TCP 443 FIRST (works on mobile data) ───
      {
        'urls': 'turns:global.relay.metered.ca:443?transport=tcp',
        'username': '7f8b9b1946d721c33e99c3aa',
        'credential': '86E+l491PG2uX7JQ',
      },
      {
        'urls': 'turn:global.relay.metered.ca:443?transport=tcp',
        'username': '7f8b9b1946d721c33e99c3aa',
        'credential': '86E+l491PG2uX7JQ',
      },
      {
        'urls': 'turn:global.relay.metered.ca:443',
        'username': '7f8b9b1946d721c33e99c3aa',
        'credential': '86E+l491PG2uX7JQ',
      },
      // ─── UDP (works on WiFi) ───
      {
        'urls': 'turn:global.relay.metered.ca:80',
        'username': '7f8b9b1946d721c33e99c3aa',
        'credential': '86E+l491PG2uX7JQ',
      },
      {
        'urls': 'turn:global.relay.metered.ca:80?transport=tcp',
        'username': '7f8b9b1946d721c33e99c3aa',
        'credential': '86E+l491PG2uX7JQ',
      },
      {'urls': 'stun:stun.l.google.com:19302'},
      {
        'urls': 'turns:freestun.net:5349',
        'username': 'free',
        'credential': 'free',
      },
      {
        'urls': 'turn:free.expressturn.com:3478',
        'username': '00000000002087100762',
        'credential': 'K2niWENTKTeRYmv/g+H2oWhLRBM=',
      },
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

  // ─── Parse ICE candidate payload safely ───
  // Appwrite Realtime sometimes returns the payload already decoded as a Map
  // instead of a raw JSON String. This guard handles both cases.
  Map<String, dynamic>? _parseCandidatePayload(dynamic raw) {
    try {
      if (raw is Map<String, dynamic>) {
        return raw;
      }
      if (raw is String) {
        return jsonDecode(raw) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _sendCandidate(RTCIceCandidate candidate) async {
    final id = _resolvedCallId;
    if (id.isEmpty) {
      return;
    }
    try {
      await CallService.addIceCandidate(
        callId: id,
        senderId: _currentUserId,
        candidate: jsonEncode({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        }),
      );
    } catch (e) {
      log('[ICE][sendCandidate] ❌ Send failed: $e');
    }
  }

  Future<void> _initCall() async {
    if (mounted) {
      ref.read(navigationProvider.notifier).state = null;
    }
    // 1. Init renderers
    try {
      if (!mounted) return;
      await _localRenderer.initialize();
      if (!mounted) return;
      await _remoteRenderer.initialize();
    } catch (e) {
      _showError('Failed to initialize video. Please try again.');
      _safePopMounted();
      return;
    }

    await CallService.clearStaleDataForUser(_currentUserId);
    if (!mounted) return;
    // 2. Get local media
    try {
      if (!mounted) return;
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo
            ? {'facingMode': 'user', 'width': 640, 'height': 480}
            : false,
      });
      if (!mounted) return;
      _localRenderer.srcObject = _localStream;
    } catch (e) {
      _showError(
        'Could not access your '
        '${widget.isVideo ? 'camera and microphone' : 'microphone'}. '
        'Please check your permissions and try again.',
      );
      _safePopMounted();
      return;
    }

    // 3. Create RTCPeerConnection
    try {
      if (!mounted) return;
      _peerConnection = await createPeerConnection(_iceServers);
    } catch (e) {
      _showError('Failed to establish connection. Please try again.');
      _safePopMounted();
      return;
    }

    // 4. Add local tracks
    for (final track in _localStream!.getTracks()) {
      try {
        if (!mounted) return;
        await _peerConnection!.addTrack(track, _localStream!);
      } catch (e) {
        _showError('Failed to set up media tracks. Please try again.');
        _safePopMounted();
        return;
      }
    }

    // 5. Listen for remote tracks.
    // Safe to register here — this callback only FIRES after a complete
    // offer/answer + ICE exchange. Registering early ensures we never miss it.
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      log(
        '🎥 [onTrack] FIRED | streams=${event.streams.length} '
        'track.kind=${event.track.kind} track.id=${event.track.id}',
      );

      if (event.streams.isEmpty) {
        return;
      }

      final stream = event.streams[0];
      log(
        '[onTrack] Stream id=${stream.id} | '
        'videoTracks=${stream.getVideoTracks().length} '
        'audioTracks=${stream.getAudioTracks().length}',
      );

      if (mounted) {
        _remoteRenderer.srcObject = stream;
        ref.read(callProvider.notifier).isConnected = true;
        _startCallTimer();
      }
    };

    // 6. ICE connection state — full diagnostic logging
    _peerConnection!
        .onIceConnectionState = (RTCIceConnectionState state) async {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        log('[ICE STATE] ✅ Connected — enabling speakerphone');
        _iceFailureCount = 0; // reset on success
        await Helper.setSpeakerphoneOn(true);
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _iceFailureCount++;
        if (_iceFailureCount < 3) {
          log(
            '[ICE STATE] ❌ Failed — restarting ICE attempt $_iceFailureCount of 3',
          );
          await _peerConnection?.restartIce();
        } else {
          if (mounted) _hangUp();
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
      final offer = await _peerConnection!.createOffer();
      final currentUserContactDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .collection('contacts')
          .doc(widget.calleeId)
          .get();

      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_currentUserId)
          .get();
      if (!mounted) return;

      await _peerConnection!.setLocalDescription(offer);
      // ice gathering starts after setLocalDescription
      if (!mounted) return;

      final doc = await CallService.createCall(
        callerId: _currentUserId,
        callerName: currentUserDoc.data()?['name'] as String? ?? '',
        callerPhoneNumber:
            currentUserDoc.data()?['phoneNumber'] as String? ?? '',
        callerProfilePicture:
            currentUserDoc.data()?['photoURL'] as String? ?? '',
        calleeId: widget.calleeId,
        calleeName:
            currentUserContactDoc.data()?['contact name'] as String? ?? '',
        calleePhoneNumber:
            currentUserContactDoc.data()?['phone number'] as String? ?? '',
        calleeProfilePicture:
            currentUserContactDoc.data()?['photoURL'] as String? ?? '',
        offer: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
        isVideo: widget.isVideo,
      );
      if (!mounted) return;

      if (doc == null) {
        _showError('Failed to start the call. Please try again.');
        _safePopMounted();
        return;
      }

      _callId = doc.$id;
      // Attach onIceCandidate only after callId is available
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) {
          return;
        }
        _sendCandidate(candidate);
      };
    } catch (e) {
      _showError('Failed to start the call. Please try again.');
      _safePopMounted();
      return;
    }

    // Subscribe to call document changes
    _callSub = CallService.subscribeToCallChanges(_callId!, (response) {
      try {
        final payload = response.payload;
        final status = payload['status'] as String?;
        // Callee hung up
        if (status == 'ended') {
          _cleanupAndPop();
          return;
        }

        if (status == 'answered') {
          final rawAnswer = payload['answer'];

          Map<String, dynamic> answerData;
          if (rawAnswer is String) {
            answerData = jsonDecode(rawAnswer);
          } else if (rawAnswer is Map<String, dynamic>) {
            answerData = rawAnswer;
          } else {
            return;
          }
          _peerConnection
              ?.setRemoteDescription(
                RTCSessionDescription(answerData['sdp'], answerData['type']),
              )
              .then((_) {
                _remoteDescSet = true;
                _flushPendingCandidates();
              });
        }
      } catch (e) {
        _showError('Connection issue. The call may drop.');
      }
    });

    // Subscribe to callee's ICE candidates
    _iceSub = CallService.subscribeToIceCandidates(_callId!, _currentUserId, (
      response,
    ) {
      try {
        final raw = response.payload['candidate'];
        final candidateData = _parseCandidatePayload(raw);
        if (candidateData == null) return;

        _handleRemoteCandidate(candidateData);
      } catch (e) {
        log('[ICE][caller←callee] ❌ Error: $e');
      }
    });
  }

  Future<void> _joinCall() async {
    // Set caller's offer as remote description first
    try {
      final offerData = jsonDecode(widget.remoteOffer!);
      if (!mounted) return;
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type']),
      );
      _remoteDescSet = true;
      _flushPendingCandidates();
    } catch (e) {
      _showError('Failed to connect to the call. Please try again.');
      _safePopMounted();
      return;
    }

    try {
      // Attach onIceCandidate after setRemoteDescription
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) {
          return;
        }
        CallService.addIceCandidate(
          callId: widget.callId!,
          senderId: _currentUserId,
          candidate: jsonEncode({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        );
      };

      final answer = await _peerConnection!.createAnswer();
      if (!mounted) return;

      await _peerConnection!.setLocalDescription(answer);
      // ice gathering now started
      if (!mounted) return;

      await CallService.answerCall(
        callId: widget.callId!,
        answer: jsonEncode({'sdp': answer.sdp, 'type': answer.type}),
      );
      if (!mounted) return;
    } catch (e) {
      _showError('Failed to connect to the call. Please try again.');
      _safePopMounted();
      return;
    }

    // Subscribe to call changes
    _callSub = CallService.subscribeToCallChanges(widget.callId!, (response) {
      try {
        final payload = response.payload;
        final status = payload['status'] as String?;

        if (status == 'ended') {
          _cleanupAndPop();
          return;
        }
      } catch (e) {
        log('[CALLEE][callSub] ❌ Error: $e');
      }
    });

    // Subscribe to caller's ICE candidates
    _iceSub = CallService.subscribeToIceCandidates(
      widget.callId!,
      _currentUserId,
      (response) {
        try {
          final raw = response.payload['candidate'];

          final candidateData = _parseCandidatePayload(raw);
          if (candidateData == null) return;

          _handleRemoteCandidate(candidateData);
        } catch (e) {
          log('[ICE][callee←caller] ❌ Error: $e');
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
      final id = _resolvedCallId;
      if (id.isNotEmpty) {
        await CallService.endCall(id);
        await CallService.cleanupCall(id);
      }
    } catch (e) {
      log('[HANGUP] ❌ Error: $e');
    } finally {
      _cleanupAndPop();
    }
  }

  void _cleanupAndPop() {
    if (!_isHangingUp) {
      _isHangingUp = true;
      if (mounted) ref.read(loadingProvider.notifier).state = true;
    }

    _callDurationTimer?.cancel();
    _callDurationTimer = null;

    try {
      _callSub?.cancel();
      _iceSub?.cancel();
      _localStream?.getTracks().forEach((track) {
        track.stop();
      });
      _localStream?.dispose();
      _peerConnection?.close();
      _peerConnection = null;
      _localRenderer.dispose();
      _remoteRenderer.dispose();
    } catch (e) {
      log('[CLEANUP] ❌ Error during cleanup: $e');
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleRemoteCandidate(Map<String, dynamic> candidateData) {
    try {
      final candidateStr = candidateData['candidate'] as String? ?? '';
      final sdpMid = candidateData['sdpMid'] as String? ?? '';
      final sdpMLineIndex = candidateData['sdpMLineIndex']?.toString() ?? '';
      final dedupeKey = '$sdpMid|$sdpMLineIndex|$candidateStr';

      if (_remoteCandidateSet.contains(dedupeKey)) {
        return;
      }
      _remoteCandidateSet.add(dedupeKey);

      if (!_remoteDescSet) {
        _pendingRemoteCandidates.add(candidateData);
        return;
      }
      _peerConnection?.addCandidate(
        RTCIceCandidate(candidateStr, sdpMid, candidateData['sdpMLineIndex']),
      );
    } catch (e) {
      log('[ICE][handleRemoteCandidate] ❌ Error: $e');
    }
  }

  void _flushPendingCandidates() {
    if (_pendingRemoteCandidates.isEmpty) {
      return;
    }
    for (final cand in _pendingRemoteCandidates) {
      try {
        final candidateStr = cand['candidate'] as String? ?? '';
        final sdpMid = cand['sdpMid'] as String? ?? '';
        _peerConnection?.addCandidate(
          RTCIceCandidate(candidateStr, sdpMid, cand['sdpMLineIndex']),
        );
      } catch (e) {
        log('[ICE][flush] ❌ Error: $e');
      }
    }
    _pendingRemoteCandidates.clear();
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

  void _safePopMounted() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  // ─── Call Duration Timer helpers ───
  void _startCallTimer() {
    if (_callDurationTimer != null) return; // already running
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        ref.read(callDurationProvider.notifier).state++;
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _callDurationTimer?.cancel();
    // Subscriptions and PC only — renderers disposed in _cleanupAndPop()
    _callSub?.cancel();
    _iceSub?.cancel();
    _localStream?.dispose();
    _peerConnection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.calleeName;
    final displayPhotoUrl = widget.callerProfilePicture;
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Consumer(
          builder: (context, ref, child) {
            final isCameraOff = ref.watch(
              callProvider.select((s) => s.isCameraOff),
            );
            final isMuted = ref.watch(callProvider.select((s) => s.isMuted));
            final isSpeaker = ref.watch(
              callProvider.select((s) => s.isSpeaker),
            );
            final isConnected = ref.watch(
              callProvider.select((s) => s.isConnected),
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

                // ── Local Video PiP ──
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
                          backgroundImage: displayPhotoUrl.isNotEmpty
                              ? NetworkImage(displayPhotoUrl)
                              : null,
                          child: displayPhotoUrl.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          displayName,
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
                              : (widget.isOnline == true
                                    ? 'Ringing...'
                                    : widget.isCaller
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

                // ── Call Duration Timer (audio call only) ──
                if (!widget.isVideo && isConnected)
                  Positioned(
                    top: 220,
                    left: 0,
                    right: 0,
                    child: Column(
                      children: [
                        const SizedBox(height: 8),
                        Icon(
                          Icons.bar_chart_rounded,
                          color: Colors.white.withOpacity(0.6),
                          size: 36,
                        ),
                        const SizedBox(height: 8),
                        Consumer(
                          builder: (context, ref, child) {
                            return Text(
                              _formatDuration(ref.watch(callDurationProvider)),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w300,
                                letterSpacing: 4,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            );
                          },
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
                            _buildControlButton(
                              icon: isMuted ? Icons.mic_off : Icons.mic,
                              label: isMuted ? 'Unmute' : 'Mute',
                              onTap: _toggleMute,
                              isActive: isMuted,
                            ),
                            _buildControlButton(
                              icon: isSpeaker
                                  ? Icons.volume_up
                                  : Icons.volume_down,
                              label: 'Speaker',
                              onTap: _toggleSpeaker,
                              isActive: isSpeaker,
                            ),
                            if (widget.isVideo)
                              _buildControlButton(
                                icon: isCameraOff
                                    ? Icons.videocam_off
                                    : Icons.videocam,
                                label: isCameraOff ? 'Camera On' : 'Camera Off',
                                onTap: _toggleCamera,
                                isActive: isCameraOff,
                              ),
                            if (widget.isVideo)
                              _buildControlButton(
                                icon: Icons.cameraswitch,
                                label: 'Flip',
                                onTap: _switchCamera,
                              ),
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
