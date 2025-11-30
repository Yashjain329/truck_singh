import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:logistics_toolkit/features/auth/utils/user_role.dart';
import 'register_screen.dart';
import 'profile_setup_page.dart';

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  final List<UserRole> _roles = const [
    UserRole.agent,
    UserRole.driver,
    UserRole.truckOwner,
    UserRole.shipper,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shadow = theme.shadowColor.withValues(alpha: .1);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        leading: BackButton(color: Colors.teal.shade800),
        title: Text('choose_your_role'.tr()),
        elevation: 0,
        backgroundColor: theme.appBarTheme.backgroundColor,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.colorScheme.surface, theme.colorScheme.surface],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _headerCard(context, shadow),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView.builder(
                    itemCount: _roles.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (_, i) => _roleCard(context, _roles[i], i),
                  ),
                ),
                _footerText(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCard(BuildContext context, Color shadow) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: shadow, blurRadius: 20, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          _iconBox([
            Colors.blue[400]!,
            Colors.blue[600]!,
          ], Icons.person_outline),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'select_role_to_continue'.tr(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'determine_dashboard'.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roleCard(BuildContext context, UserRole role, int index) {
    final theme = Theme.of(context);
    final shadow = theme.shadowColor.withValues(alpha: .1);

    return AnimatedContainer(
      duration: Duration(milliseconds: 150 + index * 60),
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _selectRole(context, role),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: shadow,
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _iconBox(
                  [
                    Colors.blue[400]!.withValues(alpha: .1),
                    Colors.blue[600]!.withValues(alpha: .2),
                  ],
                  role.icon,
                  size: 28,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _roleDescription(role),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.grey[600],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBox(List<Color> colors, IconData icon, {double size = 24}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: size, color: Colors.blue[600]),
    );
  }

  Widget _footerText() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.security, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Text(
          'info_secure'.tr(),
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    ),
  );

  String _roleDescription(UserRole role) => switch (role) {
    UserRole.agent => 'agent_desc'.tr(),
    UserRole.driver => 'driver'.tr(),
    UserRole.truckOwner => 'truck_owner_desc'.tr(),
    UserRole.shipper => 'shipper_desc'.tr(),
    _ => "",
  };

  void _selectRole(BuildContext context, UserRole role) {
    final user = Supabase.instance.client.auth.currentUser;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => user != null
            ? ProfileSetupPage(selectedRole: role)
            : RegisterPage(selectedRole: role),
      ),
    );
  }
}
