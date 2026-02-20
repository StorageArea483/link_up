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
  StreamSubscription? _callSub;
  StreamSubscription? _iceSub;

  String? _callId;
  // ignore: prefer_final_fields
  bool _isSpeaker = false;
  bool _isHangingUp = false;

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

  Future<void> _initCall() async {
    final role = widget.isCaller ? 'CALLER' : 'CALLEE';
    log(
      '[WEBRTC][INIT][START] role=$role, isVideo=${widget.isVideo}, time=${DateTime.now().toIso8601String()}',
      name: 'WEBRTC',
    );

    // 1. Init renderers
    try {
      await _localRenderer.initialize();
      if (!mounted) return;
      await _remoteRenderer.initialize();
      if (!mounted) return;
      log('[WEBRTC][INIT][RENDERERS_OK] Renderers initialized', name: 'WEBRTC');
    } catch (e) {
      log('[WEBRTC][INIT][RENDERERS_FAILED] error=$e', name: 'WEBRTC');
      _showError('Failed to initialize video. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 2. Get local media (camera + microphone)
    try {
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': widget.isVideo
            ? {'facingMode': 'user', 'width': 640, 'height': 480}
            : false,
      });
      if (!mounted) return;
      _localRenderer.srcObject = _localStream;

      final tracks = _localStream!.getTracks();
      for (final t in tracks) {
        log(
          '[WEBRTC][MEDIA][OBTAINED] kind=${t.kind}, id=${t.id}, enabled=${t.enabled}, time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );
      }
    } catch (e) {
      log('[WEBRTC][MEDIA][FAILED] error=$e', name: 'WEBRTC');
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
      _peerConnection = await createPeerConnection(_iceServers);
      if (!mounted) return;
      log(
        '[WEBRTC][PEER][CREATED] PeerConnection created, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    } catch (e) {
      log('[WEBRTC][PEER][CREATE_FAILED] error=$e', name: 'WEBRTC');
      _showError('Failed to establish connection. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // 4. Add local tracks to the peer connection
    for (final track in _localStream!.getTracks()) {
      try {
        await _peerConnection!.addTrack(track, _localStream!);
        if (!mounted) return;
        log(
          '[WEBRTC][TRACK][ADDED] kind=${track.kind}, id=${track.id}, enabled=${track.enabled}, time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );
      } catch (e) {
        log(
          '[WEBRTC][TRACK][ADD_FAILED] kind=${track.kind}, error=$e',
          name: 'WEBRTC',
        );
        _showError('Failed to set up media tracks. Please try again.');
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        return;
      }
    }

    // 5. Listen for remote tracks
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      try {
        log(
          '[WEBRTC][TRACK][REMOTE_RECEIVED] streamsCount=${event.streams.length}, track.kind=${event.track.kind}, track.id=${event.track.id}, time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );
        if (event.streams.isNotEmpty && _remoteRenderer.srcObject == null) {
          _remoteRenderer.srcObject = event.streams[0];
          log(
            '[WEBRTC][TRACK][REMOTE_ATTACHED] Remote stream attached to renderer',
            name: 'WEBRTC',
          );
          if (mounted) {
            ref.read(callProvider.notifier).isConnected = true;
          }
        }
      } catch (e) {
        log('[WEBRTC][TRACK][REMOTE_ERROR] error=$e', name: 'WEBRTC');
      }
    };

    // 6. Listen for ICE candidates and send them to Appwrite
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      log(
        '[WEBRTC][ICE][CANDIDATE_GENERATED] candidate=${candidate.candidate}, sdpMid=${candidate.sdpMid}, sdpMLineIndex=${candidate.sdpMLineIndex}, callId=$_callId, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
      if (_callId != null) {
        try {
          CallService.addIceCandidate(
            callId: _callId!,
            senderId: _currentUserId,
            candidate: jsonEncode({
              'candidate': candidate.candidate,
              'sdpMid': candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            }),
          );
          log(
            '[WEBRTC][ICE][CANDIDATE_SENT] Sent to Appwrite for callId=$_callId',
            name: 'WEBRTC',
          );
        } catch (e) {
          log('[WEBRTC][ICE][SEND_FAILED] error=$e', name: 'WEBRTC');
        }
      } else {
        log(
          '[WEBRTC][ICE][CANDIDATE_DROPPED] callId is null, candidate not sent!',
          name: 'WEBRTC',
        );
      }
    };

    // Listen for ICE gathering state
    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      log(
        '[WEBRTC][ICE][GATHERING_STATE] state=$state, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    };

    // Listen for signaling state
    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      log(
        '[WEBRTC][SIGNALING][STATE] state=$state, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    };

    // Listen for connection state
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      log(
        '[WEBRTC][PEER][CONNECTION_STATE] state=$state, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    };

    // 7. Handle ICE connection state changes
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      log(
        '[WEBRTC][ICE][CONNECTION_STATE] state=$state, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        log(
          '[WEBRTC][ICE][FAILED_OR_DISCONNECTED] Triggering hangup',
          name: 'WEBRTC',
        );
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
    log(
      '[WEBRTC][CALLER][START_CALL] Beginning call setup, time=${DateTime.now().toIso8601String()}',
      name: 'WEBRTC',
    );
    try {
      // Create SDP offer
      final offer = await _peerConnection!.createOffer();
      if (!mounted) return;
      log(
        '[WEBRTC][SDP][OFFER_CREATED] type=${offer.type}, sdpLength=${offer.sdp?.length ?? 0}, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );

      await _peerConnection!.setLocalDescription(offer);
      if (!mounted) return;
      log(
        '[WEBRTC][SDP][LOCAL_DESC_SET] type=${offer.type}, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );

      // Save to Appwrite → this creates the call document
      final doc = await CallService.createCall(
        callerId: _currentUserId,
        callerName: _currentUserName,
        calleeId: widget.calleeId,
        offer: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
        isVideo: widget.isVideo,
      );
      if (!mounted) return;

      if (doc == null) {
        log(
          '[WEBRTC][CALLER][CREATE_CALL_FAILED] Appwrite returned null doc',
          name: 'WEBRTC',
        );
        _showError('Failed to start the call. Please try again.');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      _callId = doc.$id;
      log(
        '[WEBRTC][CALLER][CALL_CREATED] callId=$_callId, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    } catch (e) {
      log('[WEBRTC][CALLER][START_CALL_FAILED] error=$e', name: 'WEBRTC');
      _showError('Failed to start the call. Please try again.');
      if (mounted) Navigator.of(context).pop();
      return;
    }

    // Subscribe to call changes (waiting for answer or ended)
    _callSub = CallService.subscribeToCallChanges(_callId!, (response) {
      try {
        final payload = response.payload;
        final status = payload['status'] as String?;
        log(
          '[WEBRTC][SIGNALING][CALL_UPDATE] status=$status, callId=$_callId, time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );

        if (status == 'answered') {
          // Callee answered → set remote description
          final answerData = jsonDecode(payload['answer'] as String);
          log(
            '[WEBRTC][SDP][REMOTE_SET_START] Setting remote answer, type=${answerData['type']}, sdpLength=${(answerData['sdp'] as String?)?.length ?? 0}',
            name: 'WEBRTC',
          );
          _peerConnection?.setRemoteDescription(
            RTCSessionDescription(answerData['sdp'], answerData['type']),
          );
          log(
            '[WEBRTC][SDP][REMOTE_SET_DONE] Remote answer set successfully, time=${DateTime.now().toIso8601String()}',
            name: 'WEBRTC',
          );
        } else if (status == 'ended') {
          log(
            '[WEBRTC][SIGNALING][CALL_ENDED] Remote side ended the call',
            name: 'WEBRTC',
          );
          _cleanupAndPop();
        }
      } catch (e) {
        log('[WEBRTC][SIGNALING][CALL_UPDATE_ERROR] error=$e', name: 'WEBRTC');
        _showError('Connection issue. The call may drop.');
      }
    });

    // Subscribe to ICE candidates from the other side
    _iceSub = CallService.subscribeToIceCandidates(_callId!, _currentUserId, (
      response,
    ) {
      try {
        final candidateData = jsonDecode(
          response.payload['candidate'] as String,
        );
        log(
          '[WEBRTC][ICE][CANDIDATE_RECEIVED] candidate=${candidateData['candidate']}, sdpMid=${candidateData['sdpMid']}, sdpMLineIndex=${candidateData['sdpMLineIndex']}, time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );
        _peerConnection?.addCandidate(
          RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          ),
        );
        log(
          '[WEBRTC][ICE][CANDIDATE_APPLIED] Candidate added to PeerConnection',
          name: 'WEBRTC',
        );
      } catch (e) {
        log(
          '[WEBRTC][ICE][CANDIDATE_APPLY_FAILED] (caller) error=$e',
          name: 'WEBRTC',
        );
      }
    });
  }

  Future<void> _joinCall() async {
    _callId = widget.callId;
    log(
      '[WEBRTC][CALLEE][JOIN_CALL] callId=$_callId, time=${DateTime.now().toIso8601String()}',
      name: 'WEBRTC',
    );

    // Set the caller's offer as remote description
    try {
      final offerData = jsonDecode(widget.remoteOffer!);
      log(
        '[WEBRTC][SDP][REMOTE_SET_START] Setting remote offer, type=${offerData['type']}, sdpLength=${(offerData['sdp'] as String?)?.length ?? 0}',
        name: 'WEBRTC',
      );
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type']),
      );
      if (!mounted) return;
      log(
        '[WEBRTC][SDP][REMOTE_SET_DONE] Remote offer set successfully, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    } catch (e) {
      log('[WEBRTC][SDP][REMOTE_SET_FAILED] error=$e', name: 'WEBRTC');
      _showError('Failed to connect to the call. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    try {
      // Create SDP answer
      final answer = await _peerConnection!.createAnswer();
      if (!mounted) return;
      log(
        '[WEBRTC][SDP][ANSWER_CREATED] type=${answer.type}, sdpLength=${answer.sdp?.length ?? 0}, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );

      await _peerConnection!.setLocalDescription(answer);
      if (!mounted) return;
      log(
        '[WEBRTC][SDP][LOCAL_DESC_SET] type=${answer.type}, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );

      // Send answer back to Appwrite
      await CallService.answerCall(
        callId: _callId!,
        answer: jsonEncode({'sdp': answer.sdp, 'type': answer.type}),
      );
      if (!mounted) return;
      log(
        '[WEBRTC][SIGNALING][ANSWER_SENT] Answer sent to Appwrite, callId=$_callId, time=${DateTime.now().toIso8601String()}',
        name: 'WEBRTC',
      );
    } catch (e) {
      log('[WEBRTC][CALLEE][ANSWER_FAILED] error=$e', name: 'WEBRTC');
      _showError('Failed to connect to the call. Please try again.');
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }

    // Subscribe to call changes (detect "ended")
    _callSub = CallService.subscribeToCallChanges(_callId!, (response) {
      try {
        final status = response.payload['status'] as String?;
        log(
          '[WEBRTC][SIGNALING][CALL_UPDATE] status=$status, callId=$_callId (callee), time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );
        if (status == 'ended') {
          log(
            '[WEBRTC][SIGNALING][CALL_ENDED] Remote side ended the call',
            name: 'WEBRTC',
          );
          _cleanupAndPop();
        }
      } catch (e) {
        log(
          '[WEBRTC][SIGNALING][CALL_UPDATE_ERROR] (callee) error=$e',
          name: 'WEBRTC',
        );
      }
    });

    // Subscribe to ICE candidates
    _iceSub = CallService.subscribeToIceCandidates(_callId!, _currentUserId, (
      response,
    ) {
      try {
        final candidateData = jsonDecode(
          response.payload['candidate'] as String,
        );
        log(
          '[WEBRTC][ICE][CANDIDATE_RECEIVED] candidate=${candidateData['candidate']}, sdpMid=${candidateData['sdpMid']}, sdpMLineIndex=${candidateData['sdpMLineIndex']}, time=${DateTime.now().toIso8601String()}',
          name: 'WEBRTC',
        );
        _peerConnection?.addCandidate(
          RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          ),
        );
        log(
          '[WEBRTC][ICE][CANDIDATE_APPLIED] Candidate added to PeerConnection (callee)',
          name: 'WEBRTC',
        );
      } catch (e) {
        log(
          '[WEBRTC][ICE][CANDIDATE_APPLY_FAILED] (callee) error=$e',
          name: 'WEBRTC',
        );
      }
    });
  }

  Future<void> _hangUp() async {
    if (_isHangingUp) return;
    _isHangingUp = true;
    if (!mounted) return;
    ref.read(loadingProvider.notifier).state = true;

    try {
      if (_callId != null) {
        await CallService.endCall(_callId!);
        await CallService.cleanupCall(_callId!);
      }
    } catch (e) {
      log('Error ending call: $e', name: 'CallScreen');
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
      log('Error during cleanup: $e', name: 'CallScreen');
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
      log('Error toggling mute: $e', name: 'CallScreen');
      _showError('Could not toggle mute. Please try again.');
    }
  }

  void _toggleSpeaker() {
    try {
      _isSpeaker = !_isSpeaker;
      if (!mounted) return;
      ref.read(callProvider.notifier).isSpeaker = _isSpeaker;
      _localStream?.getAudioTracks().forEach((track) {
        track.enableSpeakerphone(_isSpeaker);
      });
    } catch (e) {
      log('Error toggling speaker: $e', name: 'CallScreen');
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
      log('Error toggling camera: $e', name: 'CallScreen');
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
      log('Error switching camera: $e', name: 'CallScreen');
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
                if (widget.isVideo)
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
