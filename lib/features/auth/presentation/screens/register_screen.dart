import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logistics_toolkit/features/auth/presentation/screens/profile_setup_page.dart';
import 'package:logistics_toolkit/features/auth/presentation/screens/role_selection_page.dart';
import 'package:logistics_toolkit/features/auth/utils/user_role.dart';
import 'login_screen.dart';

class RegisterPage extends StatefulWidget {
  final UserRole selectedRole;
  const RegisterPage({super.key, required this.selectedRole});

  @override
  State createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with TickerProviderStateMixin {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  bool _obscureConfirm = true;
  late final FocusNode _passFocus;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _passFocus = FocusNode()..addListener(_onFocusChange);
    passCtrl.addListener(_refreshOverlay);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOut,
    );
  }

  void _onFocusChange() {
    if (_passFocus.hasFocus)
      _showOverlay();
    else
      _hideOverlay();
  }

  void _refreshOverlay() => _overlay?.markNeedsBuild();

  void _showOverlay() {
    if (_overlay != null) return;
    final overlayState = Overlay.of(context, rootOverlay: true);
    _animController.forward();
    _overlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: _overlayWidth(),
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 64),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: _ChecklistCard(
                hasMin: _hasMinLength,
                hasMax: _hasMaxLength,
                hasUpper: _hasUpper,
                hasLower: _hasLower,
                hasDigit: _hasDigit,
                hasSymbol: _hasSymbol,
              ),
            ),
          ),
        );
      },
    );
    overlayState.insert(_overlay!);
  }

  void _hideOverlay() {
    _animController.reverse().then((_) {
      _overlay?.remove();
      _overlay = null;
    });
  }

  double _overlayWidth() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) return box.size.width - 56;
    return MediaQuery.of(context).size.width * 0.75;
  }

  bool get _hasMinLength => passCtrl.text.length >= 8;
  bool get _hasMaxLength =>
      passCtrl.text.length <= 16 && passCtrl.text.isNotEmpty;
  bool get _hasUpper => passCtrl.text.contains(RegExp(r'[A-Z]'));
  bool get _hasLower => passCtrl.text.contains(RegExp(r'[a-z]'));
  bool get _hasDigit => passCtrl.text.contains(RegExp(r'[0-9]'));
  bool get _hasSymbol =>
      passCtrl.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>_\-]'));

  String? _validatePassword(String? v) {
    if (!_hasMinLength) return 'password_must_be_at_least_8_characters'.tr();
    if (!_hasMaxLength) return 'password_must_be_at_most_16_characters'.tr();
    if (!_hasUpper) return 'include_uppercase'.tr();
    if (!_hasLower) return 'include_lowercase'.tr();
    if (!_hasDigit) return 'include_digit'.tr();
    if (!_hasSymbol) return 'include_symbol'.tr();
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'please_confirm_password'.tr();
    if (v != passCtrl.text) return 'passwords_do_not_match'.tr();
    return null;
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    confirmPassCtrl.dispose();
    _passFocus.removeListener(_onFocusChange);
    _passFocus.dispose();
    _overlay?.remove();
    _animController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, IconData prefix) {
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(16));
    return InputDecoration(
      filled: true,
      labelText: label,
      prefixIcon: Icon(prefix, color: Colors.teal.shade700),
      border: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );

      if (!mounted) return;

      if (res.user != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ProfileSetupPage(selectedRole: widget.selectedRole),
              ),
            );
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'confirmation_email_sent ${emailCtrl.text.trim()}'.tr(),
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e is AuthException ? e.message : 'registration_failed'.tr();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.teal.shade800),
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
          ),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF009688), Color(0xFF26D0CE), Color(0xFF00675b)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 38,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        Text(
                          "sign_up".tr(),
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF00796B),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "your_journey_awaits".tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: emailCtrl,
                          enabled: !_loading,
                          style: const TextStyle(fontSize: 16),
                          decoration: _inputDecoration(
                            "email".tr(),
                            Icons.person_outline,
                          ),
                          validator: (val) => val == null || !val.contains('@')
                              ? 'enter_valid_email'.tr()
                              : null,
                        ),
                        const SizedBox(height: 22),
                        CompositedTransformTarget(
                          link: _layerLink,
                          child: TextFormField(
                            controller: passCtrl,
                            focusNode: _passFocus,
                            enabled: !_loading,
                            obscureText: _obscure,
                            style: const TextStyle(fontSize: 16),
                            decoration:
                                _inputDecoration(
                                  "password".tr(),
                                  Icons.lock_outline,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility
                                          : Icons.visibility_off,
                                      color: Colors.teal.shade700,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                            validator: _validatePassword,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: confirmPassCtrl,
                          enabled: !_loading,
                          obscureText: _obscureConfirm,
                          style: const TextStyle(fontSize: 16),
                          decoration:
                              _inputDecoration(
                                "confirm_password".tr(),
                                Icons.lock,
                              ).copyWith(
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.teal.shade700,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                ),
                              ),
                          validator: _validateConfirm,
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF00796B),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              textStyle: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 6,
                            ),
                            onPressed: _loading ? null : _register,
                            child: _loading
                                ? const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Text("sign_up".tr()),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginPage(),
                                  ),
                                ),
                          child: Text(
                            "already_have_account".tr(),
                            style: TextStyle(
                              color: Colors.teal.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(thickness: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  final bool hasMin, hasMax, hasUpper, hasLower, hasDigit, hasSymbol;
  const _ChecklistCard({
    required this.hasMin,
    required this.hasMax,
    required this.hasUpper,
    required this.hasLower,
    required this.hasDigit,
    required this.hasSymbol,
    Key? key,
  }) : super(key: key);

  Widget _row(bool ok, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          color: ok ? Colors.teal : Colors.grey.shade500,
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: ok ? Colors.teal.shade800 : Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.teal.shade100),
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _row(hasMin, "at_least_8_characters".tr()),
            _row(hasMax, "no_more_than_16_characters".tr()),
            _row(hasUpper, "at_least_one_uppercase".tr()),
            _row(hasLower, "at_least_one_lowercase".tr()),
            _row(hasDigit, "at_least_one_number".tr()),
            _row(hasSymbol, "at_least_one_symbol".tr()),
          ],
        ),
      ),
    );
  }
}
