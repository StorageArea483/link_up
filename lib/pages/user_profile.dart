import 'package:appwrite/appwrite.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:link_up/config/appwrite_client.dart';
import 'package:link_up/pages/google_signup.dart';
import 'package:link_up/pages/user_chats.dart';
import 'package:link_up/providers/connectivity_provider.dart';
import 'package:link_up/providers/navigation_provider.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/providers/user_profile_provider.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/widgets/app_error_widget.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/check_connection.dart';
import 'package:link_up/widgets/contact_details/edit_user_info.dart';

class UserProfile extends ConsumerStatefulWidget {
  const UserProfile({super.key});

  @override
  ConsumerState<UserProfile> createState() => _UserProfileState();
}

class _UserProfileState extends ConsumerState<UserProfile> {
  Future<bool> imagePicker(ImageSource source) async {
    try {
      final image = await ImagePicker().pickImage(source: source);
      if (image == null) return false;
      if (!context.mounted) return false;

      final networkOnlineAsync = ref.read(networkConnectivityProvider);
      final hasInternet = networkOnlineAsync.value ?? true;
      if (!hasInternet) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to upload. Please check your internet connection and try again.',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return false;

      // ✅ Use UID as deterministic fileId — always same ID per user
      final fileId = currentUser.uid;

      if (context.mounted) _showUploadingDialog();

      // ✅ Delete old file first (if exists), so we can reuse the same fileId
      try {
        await storage.deleteFile(bucketId: bucketId, fileId: fileId);
      } catch (_) {}

      // ✅ Upload new file using UID as the fileId
      await storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: InputFile.fromPath(path: image.path),
      );

      // ✅ Add timestamp to bust Flutter's image cache
      final fileUrl =
          '${client.endPoint}/storage/buckets/$bucketId/files/$fileId/view'
          '?project=${client.config['project']}&t=${DateTime.now().millisecondsSinceEpoch}';

      // ✅ Update Firestore with new photo URL
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .update({'photoURL': fileUrl});
      // Update every contacts/{doc} where this user is the contact
      final contactsSnap = await FirebaseFirestore.instance
          .collectionGroup('contacts')
          .where('uid', isEqualTo: currentUser.uid)
          .get();
      for (final doc in contactsSnap.docs) {
        await doc.reference.update({'photoURL': fileUrl});
      }

      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Profile picture updated successfully!',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      ref.invalidate(currentUserInfoProvider);
      ref.invalidate(userContactProvider);
      return true;
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Failed to update profile picture please try again.',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  void _showUploadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          backgroundColor: AppColors.primaryBlue,
        ),
      ),
    );
  }

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Select Image Source', style: AppTextStyles.title),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildImageSourceOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    imagePicker(ImageSource.camera);
                  },
                ),
                _buildImageSourceOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    imagePicker(ImageSource.gallery);
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.iconBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppColors.primaryBlue),
            const SizedBox(height: 8),
            Text(label, style: AppTextStyles.button),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (mounted) {
      ref.read(navigationProvider.notifier).state = null;
    }
    final userInfo = ref.watch(currentUserInfoProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isTablet = constraints.maxWidth >= 600;
            return AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              automaticallyImplyLeading: false,
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
                              color: AppColors.textPrimary,
                            ),
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (context) => const CheckConnection(
                                      child: UserChats(),
                                    ),
                                  ),
                                ),
                          ),
                          Expanded(
                            child: Text(
                              'Profile Page',
                              style: AppTextStyles.title.copyWith(fontSize: 20),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 48),
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
      body: userInfo.when(
        skipLoadingOnReload: false,
        skipLoadingOnRefresh: false,
        data: (data) {
          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTablet = constraints.maxWidth >= 600;
                final horizontalPadding = isTablet ? 32.0 : 20.0;
                final maxContentWidth = isTablet ? 640.0 : double.infinity;
                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxContentWidth),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 12,
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Profile Header Section
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.shadow,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  // Profile Avatar
                                  Stack(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: AppColors.primaryBlue,
                                            width: 3,
                                          ),
                                        ),
                                        child: data.isNotEmpty
                                            ? CircleAvatar(
                                                radius: 60,
                                                backgroundColor:
                                                    AppColors.iconBackground,
                                                child: ClipOval(
                                                  child: Image.network(
                                                    data['photoURL'],
                                                    width: 120,
                                                    height: 120,
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return const Icon(
                                                            Icons
                                                                .person_2_outlined,
                                                            color: AppColors
                                                                .primaryBlue,
                                                            size: 60,
                                                          );
                                                        },
                                                    loadingBuilder:
                                                        (
                                                          context,
                                                          child,
                                                          loadingProgress,
                                                        ) {
                                                          if (loadingProgress ==
                                                              null) {
                                                            return child;
                                                          }
                                                          return const Center(
                                                            child:
                                                                CircularProgressIndicator(
                                                                  strokeWidth:
                                                                      2,
                                                                ),
                                                          );
                                                        },
                                                  ),
                                                ),
                                              )
                                            : const CircleAvatar(
                                                radius: 60,
                                                backgroundColor:
                                                    AppColors.iconBackground,
                                                child: Icon(
                                                  Icons.person,
                                                  size: 60,
                                                  color:
                                                      AppColors.textSecondary,
                                                ),
                                              ),
                                      ),
                                      Positioned(
                                        bottom: 4,
                                        right: 4,
                                        child: GestureDetector(
                                          onTap: () {
                                            _showImageSourceDialog();
                                          },
                                          child: Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryBlue,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: AppColors.surface,
                                                width: 3,
                                              ),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: AppColors.shadow,
                                                  blurRadius: 8,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // User Name
                                  Text(
                                    data.isNotEmpty
                                        ? data['name']
                                        : 'Your Name',
                                    style: AppTextStyles.title.copyWith(
                                      fontSize: 24,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  // User Email
                                  Text(
                                    data.isNotEmpty
                                        ? data['email']
                                        : 'your.email@example.com',
                                    style: AppTextStyles.subtitle,
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Profile Information Section
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.shadow,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'PROFILE INFORMATION',
                                    style: AppTextStyles.sectionLabel,
                                  ),
                                  const SizedBox(height: 16),

                                  // Name Field
                                  _buildProfileField(
                                    icon: Icons.person_outline,
                                    label: 'Full Name',
                                    value: data.isNotEmpty
                                        ? data['name']
                                        : 'Not set',
                                  ),

                                  const SizedBox(height: 12),

                                  // Email Field
                                  _buildProfileField(
                                    icon: Icons.email_outlined,
                                    label: 'Email Address',
                                    value: data.isNotEmpty
                                        ? data['email']
                                        : 'Not set',
                                  ),

                                  const SizedBox(height: 12),

                                  // Phone Field
                                  _buildProfileField(
                                    icon: Icons.phone_outlined,
                                    label: 'Phone Number',
                                    value: data.isNotEmpty
                                        ? data['user phone number']
                                        : 'Not set',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Action Buttons Section
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(
                                    color: AppColors.shadow,
                                    blurRadius: 10,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'ACTIONS',
                                    style: AppTextStyles.sectionLabel,
                                  ),
                                  const SizedBox(height: 16),

                                  // Edit Profile Button
                                  _buildActionButton(
                                    icon: Icons.edit_outlined,
                                    label: 'Edit Profile',
                                    onTap: () {
                                      Navigator.of(context).pushReplacement(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const CheckConnection(
                                                child: EditUserInfo(),
                                              ),
                                        ),
                                      );
                                    },
                                  ),

                                  const SizedBox(height: 12),

                                  // Sign Out Button
                                  _buildActionButton(
                                    icon: Icons.logout_outlined,
                                    label: 'Sign Out',
                                    isDestructive: true,
                                    onTap: () async {
                                      await FirebaseAuth.instance.signOut();
                                      Navigator.of(context).pushAndRemoveUntil(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const GoogleSignup(),
                                        ),
                                        (route) => false,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
        error: (error, stackTrace) =>
            AppErrorWidget(provider: currentUserInfoProvider),
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryBlue),
        ),
      ),
      bottomNavigationBar: const BottomNavbar(currentIndex: 3),
    );
  }

  Widget _buildProfileField({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.iconBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: AppColors.primaryBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.sectionLabel.copyWith(letterSpacing: 0.5),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppTextStyles.body.copyWith(
                  color: value == 'Not set'
                      ? AppColors.textSecondary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDestructive
                ? Colors.red.withOpacity(0.3)
                : AppColors.divider,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDestructive ? Colors.red : AppColors.primaryBlue,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.button.copyWith(
                color: isDestructive ? Colors.red : AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: isDestructive
                  ? Colors.red.withOpacity(0.6)
                  : AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
