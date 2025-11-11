import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('termsConditionsTitle'.tr()),
        backgroundColor: theme.primaryColor,
        elevation: 1,
      ),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'termsConditionsTitle'.tr(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),

                _sectionTitle(theme, 'section11Title'.tr()),
                _sectionBody(theme, 'section1Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section21Title'.tr()),
                _sectionBody(theme, 'section2Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section31Title'.tr()),

                _sectionTitle(theme, 'section3_1Title'.tr()),
                _sectionBody(theme, 'section3_1Body'.tr()),

                _sectionTitle(theme, 'section3_2Title'.tr()),
                _sectionBody(theme, 'section3_2Body'.tr()),

                _sectionTitle(theme, 'section3_3Title'.tr()),
                _sectionBody(theme, 'section3_3Body'.tr()),

                _sectionTitle(theme, 'section3_4Title'.tr()),
                _sectionBody(theme, 'section3_4Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section41Title'.tr()),
                _sectionBody(theme, 'section41Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section51Title'.tr()),
                _sectionBody(theme, 'section51Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section61Title'.tr()),
                _sectionBody(theme, 'section61Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section71Title'.tr()),
                _sectionBody(theme, 'section71Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section81Title'.tr()),
                _sectionBody(theme, 'section81Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section91Title'.tr()),
                _sectionBody(theme, 'section91Body'.tr()),
                _divider(),

                _sectionTitle(theme, 'section101Title'.tr()),
                _sectionBody(theme, 'section101Body'.tr()),

                const SizedBox(height: 20),
                Text(
                  'lastUpdated'.tr(args: ['November 2025']),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.primaryColor,
        ),
      ),
    );
  }

  Widget _sectionBody(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
      ),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.only(bottom: 16.0),
    child: Divider(thickness: 0.7, height: 24, color: Colors.black12),
  );
}