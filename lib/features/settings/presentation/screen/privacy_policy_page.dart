import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  Widget _buildHeading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
      child: Text(
        text.tr(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubHeading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
      child: Text(
        text.tr(),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildBodyText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Text(
        text.tr(),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('privacyPolicyAppBarTitle'.tr()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildHeading(context, 'privacyPolicyTitle'),
          _buildHeading(context, 'section1Title'),
          _buildBodyText(context, 'section1Paragraph1'),
          _buildBodyText(context, 'section1Paragraph2'),
          _buildBodyText(context, 'section1Paragraph3'),

          _buildHeading(context, 'section2Title'),
          _buildBodyText(context, 'section2Paragraph1'),

          _buildSubHeading(context, 'section2SubA'),
          _buildBodyText(context, 'section2SubAParagraph'),

          _buildSubHeading(context, 'section2SubB'),
          _buildBodyText(context, 'section2SubBParagraph1'),
          _buildBodyText(context, 'section2SubBParagraph2'),
          _buildBodyText(context, 'section2SubBParagraph3'),
          _buildBodyText(context, 'section2SubBParagraph4'),

          _buildSubHeading(context, 'section2SubC'),
          _buildBodyText(context, 'section2SubCParagraph'),

          _buildHeading(context, 'section3Title'),
          _buildBodyText(context, 'section3Paragraph'),

          _buildHeading(context, 'section4Title'),
          _buildBodyText(context, 'section4Paragraph'),

          _buildHeading(context, 'section5Title'),
          _buildBodyText(context, 'section5Paragraph'),

          _buildHeading(context, 'section6Title'),
          _buildBodyText(context, 'section6Paragraph'),

          _buildHeading(context, 'section7Title'),
          _buildBodyText(context, 'section7Paragraph'),

          _buildHeading(context, 'section8Title'),
          _buildBodyText(context, 'section8Paragraph'),

          _buildHeading(context, 'section9Title'),
          _buildBodyText(context, 'section9Paragraph'),

          _buildHeading(context, 'section10Title'),
          _buildBodyText(context, 'section10Paragraph'),
        ],
      ),
    );
  }
}