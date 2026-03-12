import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/providers/loading_provider.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:link_up/providers/user_contacts_provider.dart';

class QrScanner extends ConsumerStatefulWidget {
  const QrScanner({super.key});

  @override
  ConsumerState<QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends ConsumerState<QrScanner> {
  final MobileScannerController _controller = MobileScannerController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleQrCode(String? scannedData) async {
    if (scannedData == null) return;

    // ✅ Prevent multiple scans firing at once
    if (ref.read(isLoadingProvider)) return;

    if (!mounted) return;
    ref.read(isLoadingProvider.notifier).state = true;

    try {
      if (!scannedData.startsWith('LINKUP:')) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR code. Please scan a LinkUp QR code.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final scannedUserId = scannedData.replaceFirst('LINKUP:', '');
      final currentUser = FirebaseAuth.instance.currentUser!;

      // Check if trying to add yourself
      if (scannedUserId == currentUser.uid) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot add yourself as a contact'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // ✅ Check if contact already exists for current user
      final existingContact = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('contacts')
          .doc(scannedUserId)
          .get();

      if (!mounted) return;

      if (existingContact.exists) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        return;
      }

      // Fetch scanned user's data
      final scannedUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(scannedUserId)
          .get();

      if (!mounted) return;

      if (!scannedUserDoc.exists) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User not found'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final scannedUserData = scannedUserDoc.data()!;

      // Fetch current user's data
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!mounted) return;

      if (!currentUserDoc.exists) {
        ref.read(isLoadingProvider.notifier).state = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not fetch your profile. Please try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final currentUserData = currentUserDoc.data()!;

      // ✅ Both writes run together — neither is skipped due to early navigation
      await Future.wait([
        // Add scanned user to current user's contacts
        FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .collection('contacts')
            .doc(scannedUserId)
            .set({
              'uid': scannedUserId,
              'contact name': scannedUserData['name'] ?? 'Unknown',
              'phone number': scannedUserData['user phone number'] ?? '',
              'photoURL': scannedUserData['photoURL'] ?? '',
            }),

        // Add current user to scanned user's contacts (mutual)
        FirebaseFirestore.instance
            .collection('users')
            .doc(scannedUserId)
            .collection('contacts')
            .doc(currentUser.uid)
            .set({
              'uid': currentUser.uid,
              'contact name': currentUserData['name'] ?? 'Unknown',
              'phone number': currentUserData['user phone number'] ?? '',
              'photoURL': currentUserData['photoURL'] ?? '',
            }),
      ]);

      if (!mounted) return;
      ref.read(isLoadingProvider.notifier).state = false;

      // ✅ Invalidate AFTER both writes are confirmed complete
      ref.invalidate(userContactProvider);
      ref.read(userContactProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact added successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => const CheckConnection(child: LandingPage()),
        ),
      );
    } catch (e) {
      ref.read(isLoadingProvider.notifier).state = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'An error occurred while adding contact, please try again later',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const CheckConnection(child: LandingPage()),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = constraints.maxWidth >= 600;
              return AppBar(
                backgroundColor: AppColors.background,
                elevation: 0,
                automaticallyImplyLeading:
                    false, // ← removes Android back button
                flexibleSpace: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isTablet ? 640.0 : double.infinity,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                              ),
                              onPressed: () =>
                                  Navigator.of(context).pushReplacement(
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const CheckConnection(
                                            child: LandingPage(),
                                          ),
                                    ),
                                  ),
                            ),
                            Expanded(
                              child: Text(
                                'Scan QR Code',
                                style: AppTextStyles.title.copyWith(
                                  fontSize: 20,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(
                              width: 48,
                            ), // balances the back button
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final List<Barcode> barcodes = capture.barcodes;
                if (barcodes.isNotEmpty) {
                  final String? code = barcodes.first.rawValue;
                  _handleQrCode(code);
                }
              },
            ),
            Consumer(
              builder: (context, ref, _) {
                return ref.watch(isLoadingProvider)
                    ? Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      )
                    : Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            'Point camera at QR code',
                            style: AppTextStyles.subtitle.copyWith(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      );
              },
            ),
          ],
        ),
      ),
    );
  }
}
