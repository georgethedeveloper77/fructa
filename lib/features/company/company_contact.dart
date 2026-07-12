import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets/kit.dart';
import '../../data/models/company.dart';

/// Contact section for the fund/company detail page. Surfaces the manager's
/// direct channels (call / WhatsApp / email / website) from the company record
/// (migrations 0028/0029, published in the snapshot). Drop it in after the
/// agents section:
///
/// ```dart
/// CompanyContact(company: ref.watch(companiesProvider)[fund.companyId]),
/// ```
///
/// Hides itself entirely when the company is null or carries no channels, and
/// hides any individual channel that's blank, so an unseeded manager shows
/// nothing rather than empty rows.
class CompanyContact extends StatelessWidget {
  const CompanyContact({super.key, required this.company});

  final Company? company;

  bool _has(Company co) =>
      co.phone != null ||
      co.whatsapp != null ||
      co.email != null ||
      co.website != null;

  @override
  Widget build(BuildContext context) {
    final co = company;
    if (co == null || !_has(co)) return const SizedBox.shrink();
    final c = context.c;

    final grid = <Widget>[
      if (co.phone != null)
        _ContactTile(
          icon: Icons.call,
          bg: c.upSoft,
          fg: c.up,
          label: t('company.call'),
          value: co.phone!,
          onTap: () => _open(Uri.parse('tel:${_digits(co.phone!)}')),
        ),
      if (co.whatsapp != null)
        _ContactTile(
          whatsApp: true,
          bg: const Color(0x2225D366),
          fg: const Color(0xFF25D366),
          label: t('company.whatsapp'),
          value: co.whatsapp!,
          onTap: () =>
              _open(Uri.parse('https://wa.me/${_digits(co.whatsapp!)}')),
        ),
      if (co.email != null)
        _ContactTile(
          icon: Icons.mail_outline,
          bg: c.accentSoft,
          fg: c.accent,
          label: t('company.email'),
          value: co.email!,
          onTap: () => _open(Uri.parse('mailto:${co.email!}')),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
          child: Text(
            t('company.contact').toUpperCase(),
            style: TextStyle(
                color: c.faint,
                fontSize: 11,
                letterSpacing: 0.9,
                fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              if (grid.isNotEmpty)
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 9,
                  crossAxisSpacing: 9,
                  childAspectRatio: 3.3,
                  children: grid,
                ),
              if (co.website != null) ...[
                if (grid.isNotEmpty) const SizedBox(height: 9),
                _ContactTile(
                  icon: Icons.language,
                  bg: c.s3,
                  fg: c.muted,
                  label: t('company.website'),
                  value: co.website!,
                  onTap: () => _open(Uri.parse(co.website!.startsWith('http')
                      ? co.website!
                      : 'https://${co.website!}')),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

Future<void> _open(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.bg,
    required this.fg,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.whatsApp = false,
  });

  final Color bg;
  final Color fg;
  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData? icon;
  final bool whatsApp;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: whatsApp
                  ? const WhatsAppMark(size: 17)
                  : Icon(icon, size: 15, color: fg),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: c.faint,
                          fontSize: 9,
                          letterSpacing: 0.7,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(value,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: fructaFonts.mono)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
