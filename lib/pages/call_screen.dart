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
  final String? callId;
  final String? remoteOffer;

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
  final Set<String> _remoteCandidateSet = <String>{};
  final List<Map<String, dynamic>> _pendingRemoteCandidates = [];

  // ─── Current User ───
  String get _currentUserId => FirebaseAuth.instance.currentUser!.uid;
  String get _currentUserName =>
      FirebaseAuth.instance.currentUser!.displayName ?? 'Unknown';

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // Metered
      {
        'urls': 'turn:relay.metered.ca:80',
        'username': 'e8dd65f932c59bfa258b9f6c',
        'credential': 'uMpMLMaBIBTBoBne',
      },
      {
        'urls': 'turns:relay.metered.ca:443',
        'username': 'e8dd65f932c59bfa258b9f6c',
        'credential': 'uMpMLMaBIBTBoBne',
      },
      // FreeStn backup
      {
        'urls': 'turn:freestun.net:3478',
        'username': 'free',
        'credential': 'free',
      },
      {
        'urls': 'turns:freestun.net:5349',
        'username': 'free',
        'credential': 'free',
      },
      // ExpressTURN backup
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
        log('[ICE][parse] Payload was already a Map (Appwrite pre-decoded)');
        return raw;
      }
      if (raw is String) {
        log('[ICE][parse] Payload is a String — running jsonDecode');
        return jsonDecode(raw) as Map<String, dynamic>;
      }
      log(
        '[ICE][parse] ⚠️ Unexpected payload type: ${raw.runtimeType} value=$raw',
      );
      return null;
    } catch (e) {
      log('[ICE][parse] ❌ Failed to parse candidate payload: $e | raw=$raw');
      return null;
    }
  }

  Future<void> _sendCandidate(RTCIceCandidate candidate) async {
    final id = _resolvedCallId;
    if (id.isEmpty) {
      log('[ICE][sendCandidate] ⚠️ Skipped — callId is empty');
      return;
    }
    try {
      log(
        '[ICE][sendCandidate] → sdpMid=${candidate.sdpMid} '
        'mLineIndex=${candidate.sdpMLineIndex} '
        'len=${candidate.candidate?.length ?? 0}',
      );
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
    log(
      '=== [INIT] Starting _initCall | role=${widget.isCaller ? "CALLER" : "CALLEE"} isVideo=${widget.isVideo} ===',
    );

    // 1. Init renderers
    try {
      if (!mounted) return;
      await _localRenderer.initialize();
      if (!mounted) return;
      await _remoteRenderer.initialize();
      log('[INIT] ✅ Renderers initialized');
    } catch (e) {
      log('[INIT] ❌ Renderer init failed: $e');
      _showError('Failed to initialize video. Please try again.');
      _safePop();
      return;
    }

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
      log(
        '[INIT] ✅ Local media acquired | '
        'audioTracks=${_localStream!.getAudioTracks().length} '
        'videoTracks=${_localStream!.getVideoTracks().length}',
      );
    } catch (e) {
      log('[INIT] ❌ getUserMedia failed: $e');
      _showError(
        'Could not access your '
        '${widget.isVideo ? 'camera and microphone' : 'microphone'}. '
        'Please check your permissions and try again.',
      );
      _safePop();
      return;
    }

    // 3. Create RTCPeerConnection
    try {
      if (!mounted) return;
      _peerConnection = await createPeerConnection(_iceServers);
      log('[INIT] ✅ PeerConnection created');
      // ── TURN REACHABILITY TEST ──
      log('🔬 [TURN TEST] Starting — watch for typ relay candidates');
      _peerConnection!.onIceCandidate = (RTCIceCandidate c) {
        if (c.candidate != null) {
          log('🔬 [TURN TEST] candidate: ${c.candidate}');
          if (c.candidate!.contains('typ relay')) {
            log('🔬 [TURN TEST] ✅ TURN IS WORKING — relay candidate found!');
          }
        }
      };
    } catch (e) {
      log('[INIT] ❌ createPeerConnection failed: $e');
      _showError('Failed to establish connection. Please try again.');
      _safePop();
      return;
    }

    // 4. Add local tracks
    for (final track in _localStream!.getTracks()) {
      try {
        if (!mounted) return;
        await _peerConnection!.addTrack(track, _localStream!);
        log('[INIT] ✅ Local track added → kind=${track.kind} id=${track.id}');
      } catch (e) {
        log('[INIT] ❌ addTrack failed: $e');
        _showError('Failed to set up media tracks. Please try again.');
        _safePop();
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
        log('[onTrack] ⚠️ No streams in event — skipping');
        return;
      }

      final stream = event.streams[0];
      log(
        '[onTrack] Stream id=${stream.id} | '
        'videoTracks=${stream.getVideoTracks().length} '
        'audioTracks=${stream.getAudioTracks().length}',
      );

      if (mounted) {
        setState(() {
          _remoteRenderer.srcObject = stream;
        });
        ref.read(callProvider.notifier).isConnected = true;
        log('[onTrack] ✅ Remote renderer attached + isConnected = true');
      }
    };

    // 6. ICE connection state — full diagnostic logging
    _peerConnection!
        .onIceConnectionState = (RTCIceConnectionState state) async {
      log('🧊 [ICE STATE] → $state');

      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        log('[ICE STATE] ✅ Connected — enabling speakerphone');
        await Helper.setSpeakerphoneOn(true);
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        log('[ICE STATE] ⚠️ Disconnected (transient) — waiting for recovery');
      }

      // ── CHANGED: Add 10 second delay before giving up ──
      // This gives TURN relay candidates time to be exchanged and tested
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        log('[ICE STATE] ❌ Failed — waiting 10s before hanging up');
        await Future.delayed(const Duration(seconds: 10));
        // Check state again — it may have recovered
        if (_isHangingUp) return;
        final currentState = await _peerConnection?.getStats();
        log('[ICE STATE] Hanging up after timeout');
        if (mounted) _hangUp();
      }
    };

    // 7. ICE gathering state — tells us if candidates are being found
    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      log('🔍 [ICE GATHERING] → $state');
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete) {
        log('[ICE GATHERING] ✅ Gathering complete');
      }
    };

    // 8. Signaling state — tells us if SDP exchange is progressing correctly
    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      log('📡 [SIGNALING STATE] → $state');
    };

    // 9. Overall connection state
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      log('🔗 [CONNECTION STATE] → $state');
    };

    log(
      '[INIT] ✅ All handlers registered — proceeding as ${widget.isCaller ? "CALLER" : "CALLEE"}',
    );

    if (widget.isCaller) {
      await _startCall();
    } else {
      await _joinCall();
    }
  }

  Future<void> _startCall() async {
    log('=== [CALLER] _startCall begin ===');
    try {
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideo,
      });
      log(
        '[CALLER] ✅ Offer created | type=${offer.type} sdpLen=${offer.sdp?.length ?? 0}',
      );
      if (!mounted) return;

      await _peerConnection!.setLocalDescription(offer);
      log('[CALLER] ✅ setLocalDescription done — ICE gathering now started');
      if (!mounted) return;

      final doc = await CallService.createCall(
        callerId: _currentUserId,
        callerName: _currentUserName,
        calleeId: widget.calleeId,
        offer: jsonEncode({'sdp': offer.sdp, 'type': offer.type}),
        isVideo: widget.isVideo,
      );
      if (!mounted) return;

      if (doc == null) {
        log('[CALLER] ❌ createCall returned null');
        _showError('Failed to start the call. Please try again.');
        _safePopMounted();
        return;
      }

      _callId = doc.$id;
      log('[CALLER] ✅ Call document created | callId=$_callId');

      // Attach onIceCandidate only after callId is available
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) {
          log('[ICE][caller] End-of-candidates signal received');
          return;
        }
        log(
          '[ICE][caller] New candidate | sdpMid=${candidate.sdpMid} '
          'mLineIndex=${candidate.sdpMLineIndex} '
          'len=${candidate.candidate!.length}',
        );
        _sendCandidate(candidate);
      };
    } catch (e) {
      log('[CALLER] ❌ _startCall failed: $e');
      _showError('Failed to start the call. Please try again.');
      _safePopMounted();
      return;
    }

    // Subscribe to call document changes
    _callSub = CallService.subscribeToCallChanges(_callId!, (response) {
      try {
        final payload = response.payload;
        final status = payload['status'] as String?;
        log(
          '[CALLER][callSub] event received | status=$status | keys=${payload.keys.toList()}',
        );

        // Callee hung up
        if (status == 'ended') {
          log('[CALLER][callSub] status=ended → cleaning up');
          _cleanupAndPop();
          return;
        }

        if (status == 'answered') {
          log('[CALLER][callSub] status=answered → setting remote description');
          final rawAnswer = payload['answer'];
          log('[CALLER][callSub] raw answer type=${rawAnswer.runtimeType}');

          Map<String, dynamic> answerData;
          if (rawAnswer is String) {
            answerData = jsonDecode(rawAnswer);
          } else if (rawAnswer is Map<String, dynamic>) {
            answerData = rawAnswer;
          } else {
            log(
              '[CALLER][callSub] ❌ Unexpected answer type: ${rawAnswer.runtimeType}',
            );
            return;
          }

          log(
            '[CALLER][callSub] Answer parsed | type=${answerData['type']} '
            'sdpLen=${(answerData['sdp'] as String).length}',
          );

          _peerConnection
              ?.setRemoteDescription(
                RTCSessionDescription(answerData['sdp'], answerData['type']),
              )
              .then((_) {
                log('[CALLER] ✅ setRemoteDescription done');
                _remoteDescSet = true;
                _flushPendingCandidates();
              })
              .catchError((e) {
                log('[CALLER] ❌ setRemoteDescription error: $e');
              });
        }
      } catch (e) {
        log('[CALLER][callSub] ❌ Error: $e');
        _showError('Connection issue. The call may drop.');
      }
    });

    // Subscribe to callee's ICE candidates
    _iceSub = CallService.subscribeToIceCandidates(_callId!, _currentUserId, (
      response,
    ) {
      try {
        log('[ICE][caller←callee] Raw payload: ${response.payload}');
        final raw = response.payload['candidate'];
        log(
          '[ICE][caller←callee] candidate field | type=${raw.runtimeType} | value=$raw',
        );

        final candidateData = _parseCandidatePayload(raw);
        if (candidateData == null) return;

        _handleRemoteCandidate(candidateData, direction: 'caller←callee');
      } catch (e) {
        log('[ICE][caller←callee] ❌ Error: $e');
      }
    });

    log('[CALLER] ✅ Subscriptions active — waiting for callee to answer');
  }

  Future<void> _joinCall() async {
    log('=== [CALLEE] _joinCall begin | callId=${widget.callId} ===');

    // Set caller's offer as remote description first
    try {
      log('[CALLEE] Raw remoteOffer type=${widget.remoteOffer.runtimeType}');
      final offerData = jsonDecode(widget.remoteOffer!);
      log(
        '[CALLEE] Offer parsed | type=${offerData['type']} '
        'sdpLen=${(offerData['sdp'] as String).length}',
      );

      if (!mounted) return;
      await _peerConnection!.setRemoteDescription(
        RTCSessionDescription(offerData['sdp'], offerData['type']),
      );
      log('[CALLEE] ✅ setRemoteDescription done');
      _remoteDescSet = true;
      _flushPendingCandidates();
    } catch (e) {
      log('[CALLEE] ❌ setRemoteDescription failed: $e');
      _showError('Failed to connect to the call. Please try again.');
      _safePopMounted();
      return;
    }

    try {
      // Attach onIceCandidate after setRemoteDescription
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        if (candidate.candidate == null) {
          log('[ICE][callee] End-of-candidates signal received');
          return;
        }
        log(
          '[ICE][callee] New candidate | sdpMid=${candidate.sdpMid} '
          'mLineIndex=${candidate.sdpMLineIndex} '
          'len=${candidate.candidate!.length}',
        );
        CallService.addIceCandidate(
          callId: widget.callId!,
          senderId: _currentUserId,
          candidate: jsonEncode({
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          }),
        ).catchError((e) => log('[ICE][callee] ❌ Send failed: $e'));
      };

      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': widget.isVideo,
      });
      log(
        '[CALLEE] ✅ Answer created | type=${answer.type} sdpLen=${answer.sdp?.length ?? 0}',
      );
      if (!mounted) return;

      await _peerConnection!.setLocalDescription(answer);
      log('[CALLEE] ✅ setLocalDescription done — ICE gathering now started');
      if (!mounted) return;

      await CallService.answerCall(
        callId: widget.callId!,
        answer: jsonEncode({'sdp': answer.sdp, 'type': answer.type}),
      );
      log('[CALLEE] ✅ Answer sent to Appwrite');
      if (!mounted) return;
    } catch (e) {
      log('[CALLEE] ❌ _joinCall setup failed: $e');
      _showError('Failed to connect to the call. Please try again.');
      _safePopMounted();
      return;
    }

    // Subscribe to call changes
    _callSub = CallService.subscribeToCallChanges(widget.callId!, (response) {
      try {
        final payload = response.payload;
        final status = payload['status'] as String?;
        log('[CALLEE][callSub] event received | status=$status');

        if (status == 'ended') {
          log('[CALLEE][callSub] status=ended → cleaning up');
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
          log('[ICE][callee←caller] Raw payload: ${response.payload}');
          final raw = response.payload['candidate'];
          log(
            '[ICE][callee←caller] candidate field | type=${raw.runtimeType} | value=$raw',
          );

          final candidateData = _parseCandidatePayload(raw);
          if (candidateData == null) return;

          _handleRemoteCandidate(candidateData, direction: 'callee←caller');
        } catch (e) {
          log('[ICE][callee←caller] ❌ Error: $e');
        }
      },
    );

    log('[CALLEE] ✅ Subscriptions active');
  }

  Future<void> _hangUp() async {
    if (_isHangingUp) return;
    _isHangingUp = true;
    log('=== [HANGUP] Initiated ===');
    if (!mounted) return;
    ref.read(loadingProvider.notifier).state = true;

    try {
      final id = _resolvedCallId;
      if (id.isNotEmpty) {
        log('[HANGUP] Ending call id=$id');
        await CallService.endCall(id);
        await CallService.cleanupCall(id);
        log('[HANGUP] ✅ Call ended and cleaned up');
      } else {
        log('[HANGUP] ⚠️ No call ID available');
      }
    } catch (e) {
      log('[HANGUP] ❌ Error: $e');
    } finally {
      _cleanupAndPop();
    }
  }

  void _cleanupAndPop() {
    log('[CLEANUP] _cleanupAndPop called');
    if (!_isHangingUp) {
      _isHangingUp = true;
      if (mounted) ref.read(loadingProvider.notifier).state = true;
    }

    try {
      _callSub?.cancel();
      _iceSub?.cancel();
      _localStream?.getTracks().forEach((track) {
        track.stop();
        log('[CLEANUP] Track stopped: ${track.kind}');
      });
      _localStream?.dispose();
      _peerConnection?.close();
      _peerConnection = null;
      _localRenderer.dispose();
      _remoteRenderer.dispose();
      log('[CLEANUP] ✅ All resources released');
    } catch (e) {
      log('[CLEANUP] ❌ Error during cleanup: $e');
    }

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleRemoteCandidate(
    Map<String, dynamic> candidateData, {
    required String direction,
  }) {
    try {
      final candidateStr = candidateData['candidate'] as String? ?? '';
      final sdpMid = candidateData['sdpMid'] as String? ?? '';
      final sdpMLineIndex = candidateData['sdpMLineIndex']?.toString() ?? '';
      final dedupeKey = '$sdpMid|$sdpMLineIndex|$candidateStr';

      if (_remoteCandidateSet.contains(dedupeKey)) {
        log('[ICE][dedupe] Ignoring duplicate ($direction)');
        return;
      }
      _remoteCandidateSet.add(dedupeKey);

      if (!_remoteDescSet) {
        log(
          '[ICE][buffer] Buffering ($direction) | '
          'sdpMid=$sdpMid mLineIndex=$sdpMLineIndex len=${candidateStr.length} | '
          'buffer size=${_pendingRemoteCandidates.length + 1}',
        );
        _pendingRemoteCandidates.add(candidateData);
        return;
      }

      log(
        '[ICE][add] ($direction) | '
        'sdpMid=$sdpMid mLineIndex=$sdpMLineIndex len=${candidateStr.length}',
      );
      _peerConnection?.addCandidate(
        RTCIceCandidate(candidateStr, sdpMid, candidateData['sdpMLineIndex']),
      );
    } catch (e) {
      log('[ICE][handleRemoteCandidate] ❌ Error: $e');
    }
  }

  void _flushPendingCandidates() {
    if (_pendingRemoteCandidates.isEmpty) {
      log('[ICE][flush] Nothing to flush');
      return;
    }
    log(
      '[ICE][flush] Flushing ${_pendingRemoteCandidates.length} buffered candidates',
    );
    for (final cand in List<Map<String, dynamic>>.from(
      _pendingRemoteCandidates,
    )) {
      try {
        final candidateStr = cand['candidate'] as String? ?? '';
        final sdpMid = cand['sdpMid'] as String? ?? '';
        log('[ICE][flush] Adding sdpMid=$sdpMid len=${candidateStr.length}');
        _peerConnection?.addCandidate(
          RTCIceCandidate(candidateStr, sdpMid, cand['sdpMLineIndex']),
        );
      } catch (e) {
        log('[ICE][flush] ❌ Error: $e');
      }
    }
    _pendingRemoteCandidates.clear();
    log('[ICE][flush] ✅ Flush complete');
  }

  void _toggleMute() {
    try {
      final audioTracks = _localStream?.getAudioTracks();
      if (audioTracks != null && audioTracks.isNotEmpty) {
        final enabled = !audioTracks[0].enabled;
        audioTracks[0].enabled = enabled;
        log('[UI] Mute toggled → muted=${!enabled}');
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
      log('[UI] Speaker toggled → speaker=$_isSpeaker');
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
        log('[UI] Camera toggled → cameraOff=${!enabled}');
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
        log('[UI] Camera switched');
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

  void _safePop() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    // Subscriptions and PC only — renderers disposed in _cleanupAndPop()
    _callSub?.cancel();
    _iceSub?.cancel();
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
