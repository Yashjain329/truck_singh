import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class NotificationDetailsPage extends StatelessWidget {
  const NotificationDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double width = size.width;
    final bool isTablet = width > 600 && width <= 1000;
    final bool isDesktop = width > 1000;
    final double titleSize = isDesktop
        ? 32
        : isTablet
        ? 28
        : 26;

    final double bodyFontSize = isDesktop
        ? 16
        : isTablet
        ? 15
        : 14.5;

    const double maxContentWidth = 600;

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        title: Text(
          'notificationDetailsTitle'.tr(),
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxContentWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop
                    ? 48
                    : isTablet
                    ? 32
                    : 16,
                vertical: isDesktop
                    ? 40
                    : isTablet
                    ? 28
                    : 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 24),

                  _buildCard(
                    title: 'shipmentNotificationsTitle'.tr(),
                    description: 'shipmentNotificationsDescription'.tr(),
                    context: context,
                    fontSize: bodyFontSize,
                  ),

                  _buildCard(
                    title: 'driverSOSAlertsTitle'.tr(),
                    description: 'driverSOSAlertsDescription'.tr(),
                    context: context,
                    fontSize: bodyFontSize,
                  ),

                  _buildCard(
                    title: 'adminAccountTitle'.tr(),
                    description: 'adminAccountDescription'.tr(),
                    context: context,
                    fontSize: bodyFontSize,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String description,
    required BuildContext context,
    required double fontSize,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black12.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}