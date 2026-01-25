import 'package:appwrite/models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:link_up/pages/landing_page.dart';
import 'package:link_up/services/chat_service.dart';
import 'package:link_up/styles/styles.dart';
import 'package:link_up/providers/user_contacts_provider.dart';
import 'package:link_up/widgets/bottom_navbar.dart';
import 'package:link_up/widgets/chat_storage/chat_screen.dart';

class UserChats extends ConsumerStatefulWidget {
  const UserChats({super.key});

  @override
  ConsumerState<UserChats> createState() => _UserChatsState();
}

class _UserChatsState extends ConsumerState<UserChats> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LandingPage()),
        );
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          title: const Text('User Chats', style: AppTextStyles.title),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const LandingPage()),
            ),
          ),
        ),
        body: SafeArea(
          child: Consumer(
            builder: (context, ref, _) {
              final contactsAsyncValue = ref.watch(userContactProvider);
              return contactsAsyncValue.when(
                skipLoadingOnRefresh: false,
                skipLoadingOnReload: false,
                data: (contacts) {
                  if (contacts.isEmpty) {
                    return const SingleChildScrollView(
                      physics: AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: 600,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_2_outlined,
                                size: 100,
                                color: AppColors.textPrimary,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'No registered contacts found.',
                                style: AppTextStyles.subtitle,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: contacts.length,
                    itemBuilder: (context, index) {
                      final contact = contacts[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          leading: CircleAvatar(
                            radius: 32,
                            backgroundColor: AppColors.primaryBlue.withOpacity(
                              0.2,
                            ),
                            child: ClipOval(
                              child: Image.network(
                                contact.profilePicture,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return const Icon(
                                    Icons.person_2_outlined,
                                    color: AppColors.primaryBlue,
                                    size: 32,
                                  );
                                },
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const CircularProgressIndicator(
                                        strokeWidth: 2,
                                      );
                                    },
                              ),
                            ),
                          ),
                          title: Text(
                            contact.name,
                            style: AppTextStyles.button.copyWith(fontSize: 18),
                          ),
                          subtitle: FutureBuilder<DocumentList>(
                            future: () async {
                              final currentUserId =
                                  FirebaseAuth.instance.currentUser?.uid;
                              if (currentUserId == null) {
                                return DocumentList(total: 0, documents: []);
                              }
                              final chatId = ChatService.generateChatId(
                                currentUserId,
                                contact.uid,
                              );
                              return ChatService.getLastMessage(chatId);
                            }(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData &&
                                  snapshot.data!.documents.isNotEmpty) {
                                final lastMsg =
                                    snapshot
                                        .data!
                                        .documents
                                        .first
                                        .data['text'] ??
                                    '';
                                return Text(
                                  lastMsg,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.subtitle.copyWith(
                                    fontSize: 14,
                                  ),
                                );
                              }
                              return Text(
                                '',
                                style: AppTextStyles.subtitle.copyWith(
                                  fontSize: 14,
                                ),
                              );
                            },
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                          onTap: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (context) =>
                                    ChatScreen(contact: contact),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryBlue,
                  ),
                ),
                error: (err, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'An error occurred while loading products',
                        style: AppTextStyles.subtitle,
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: AppColors.white,
                        ),
                        onPressed: () => ref.invalidate(userContactProvider),
                        label: const Text("Retry"),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: const BottomNavbar(currentIndex: 2),
      ),
    );
  }
}
