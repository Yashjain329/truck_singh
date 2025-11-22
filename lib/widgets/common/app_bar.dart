import 'dart:async';
import 'package:flutter/material.dart';
import 'package:logistics_toolkit/features/notifications/presentation/screen/notification_center.dart';
import 'package:logistics_toolkit/features/settings/presentation/screen/settings_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/notifications/notification_service.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String? pageTitle;
  final bool showProfile;
  final bool showNotifications;
  final bool showMessages;
  final List<Widget>? customActions;
  final VoidCallback? onProfileTap;
  final Map<String, dynamic>? userProfile;
  final bool isLoading;
  final Map<String, dynamic>? shipment;

  const CustomAppBar({
    super.key,
    this.pageTitle,
    this.showProfile = false,
    this.showNotifications = true,
    this.showMessages = true,
    this.customActions,
    this.onProfileTap,
    this.userProfile,
    this.isLoading = false,
    this.shipment,
  });

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _CustomAppBarState extends State<CustomAppBar> {

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppBar(
      elevation: 0,
      backgroundColor:
      theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
      foregroundColor:
      theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
      leading: widget.pageTitle != null
          ? IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      )
          : null,
      title: widget.showProfile
          ? _buildProfileTitle(context)
          : _buildPageTitle(context),
      actions: _buildActions(context),
    );
  }

  Widget _buildProfileTitle(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.isLoading) {
      return _buildLoadingTitle();
    }

    if (widget.userProfile == null) {
      return Row(
        children: [
          CircleAvatar(
            backgroundColor: colorScheme.errorContainer,
            child: Icon(Icons.error, color: colorScheme.onErrorContainer),
          ),
          const SizedBox(width: 12),
          Text('Error loading profile', style: theme.textTheme.titleMedium),
        ],
      );
    }

    final profile = widget.userProfile!;
    return GestureDetector(
      onTap:
      widget.onProfileTap ??
              () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettingsPage()),
          ),
      child: Row(
        children: [
          profile['profile_picture'] != null &&
              profile['profile_picture'].isNotEmpty
              ? CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.primaryContainer,
            backgroundImage: NetworkImage(profile['profile_picture']),
          )
              : CircleAvatar(
            radius: 20,
            backgroundColor: colorScheme.primaryContainer,
            child: Icon(
              Icons.person,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Hello, ${profile['name']?.split(' ').first ?? 'User'}',
                  style: theme.textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'ID: ${profile['custom_user_id'] ?? 'N/A'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTitle(BuildContext context) {
    return Text(
      widget.pageTitle ?? '',
      style: Theme.of(context).textTheme.titleLarge,
    );
  }

  Widget _buildLoadingTitle() {
    return Row(
      children: [
        const CircleAvatar(backgroundColor: Colors.black12),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 80,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    List<Widget> actions = [];

    if (widget.customActions != null) {
      actions.addAll(widget.customActions!);
    }
    if (widget.showNotifications) {
      actions.add(_buildNotificationButton());
    }
    return actions;
  }

  Widget _buildNotificationButton() {
    return StreamBuilder<int>(
      stream: NotificationService.getUnreadCountStream(),
      builder: (context, snapshot) {
        int unreadCount = 0;
        if (snapshot.hasData) {
          unreadCount = snapshot.data!;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationCenterPage()),
                );
              },
            ),
            if (unreadCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}