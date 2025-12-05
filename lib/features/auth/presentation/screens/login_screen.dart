import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../widgets/chat_screen.dart';
import '../../../../widgets/floating_chat_control.dart';
import 'reset_password_screen.dart';
import 'role_selection_page.dart';
import 'dashboard_router.dart';
import '../../utils/user_role.dart';
import '../../../disable/unable_account_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with WidgetsBindingObserver {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscureText = true;
  bool _loading = false;
  bool _oauthInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) _checkForOAuthCompletion();
  }

  void _checkForOAuthCompletion() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser != null && mounted) _handleSuccessfulLogin(currentUser);
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text.trim();

    try {
      final res = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);

      if (res.user != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login successful!')),
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await _handleSuccessfulLogin(res.user!);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("login_failed".tr())));
      }
    } on AuthException catch (e) {
      if (e.message.contains('Invalid login credentials') ||
          e.message.contains('Email not confirmed')) {
        await _handlePossibleOAuthUser(email);
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("login_failed".tr())));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithProvider(OAuthProvider provider) async {
    if (_oauthInProgress) return;
    setState(() {
      _loading = true;
      _oauthInProgress = true;
    });

    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: 'com.login.app://login-callback',
      );
      await Future.delayed(const Duration(milliseconds: 500));
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && mounted) {
        setState(() {
          _loading = false;
          _oauthInProgress = false;
        });
        await _handleSuccessfulLogin(user);
        return;
      }

      _startOAuthCallbackDetection();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _oauthInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Social login failed: ${e.toString()}")),
        );
      }
    }
  }

  void _startOAuthCallbackDetection() {
    Timer.periodic(const Duration(milliseconds: 200), (timer) {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _loading = false;
            _oauthInProgress = false;
          });
          _handleSuccessfulLogin(currentUser);
        }
      } else if (timer.tick > 150) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _loading = false;
            _oauthInProgress = false;
          });
        }
      }
    });
  }

  Future<void> _handleSuccessfulLogin(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_user_id', user.id);
    } catch (_) {}

    try {
      final userProfile = await Supabase.instance.client
          .from('user_profiles')
          .select('role, account_disable, profile_completed, custom_user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (userProfile == null) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
          );
        }
        return;
      }

      final isDisabled = userProfile['account_disable'] as bool? ?? false;
      if (isDisabled) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => UnableAccountPage(userProfile: userProfile),
            ),
          );
        }
        return;
      }

      final isProfileCompleted = userProfile['profile_completed'] as bool? ?? false;
      final role = userProfile['role'];
      final customUserId = userProfile['custom_user_id'] as String?;

      if (!isProfileCompleted || role == null) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
          );
        }
        return;
      }

      if (customUserId != null) {
        OneSignal.login(customUserId);
      }

      final userRole = UserRoleExtension.fromDbValue(role);
      if (userRole != null && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => DashboardRouter(role: userRole)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Login successful but navigation failed. Please restart the app.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _handlePossibleOAuthUser(String email) async {
    try {
      final existingUser = await Supabase.instance.client
          .from('user_profiles')
          .select('email, user_id')
          .eq('email', email)
          .maybeSingle();

      if (existingUser != null) {
        _showOAuthRequiredDialog();
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Invalid email or password")));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("login_failed".tr())));
      }
    }
  }

  void _showOAuthRequiredDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Use Google Sign-In"),
        content: const Text(
          "This email is linked to Google sign-in. "
              "Please use 'Continue with Google' to access your account.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _signInWithProvider(OAuthProvider.google);
            },
            child: const Text("Sign in with Google"),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData prefixIcon) => InputDecoration(
    filled: true,
    labelText: label,
    prefixIcon: Icon(prefixIcon, color: Colors.teal.shade700),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.teal.shade700, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.redAccent, width: 2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.redAccent, width: 2),
    ),
  );

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('chooseLanguage'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('English'.tr()), onTap: () { context.setLocale(const Locale('en')); Navigator.pop(context); }),
            ListTile(title: Text("हिंदी".tr()), onTap: () { context.setLocale(const Locale('hi')); Navigator.pop(context); }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF009688), Color(0xFF26D0CE), Color(0xFF00675b)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          alignment: Alignment.center,
          child: Stack(
            children: [
              Center(child: _buildCard(context)),
              Positioned(top: 100, right: 60, child: _languageButton()),
              FloatingChatControl(
                onOpenChat: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        onNavigate: (s) {
                          Navigator.of(context).pushNamed('/$s');
                        },
                      ),
                    ),
                  );
                },
                listening: false,
              ),
            ],
          ),

        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Material(
        elevation: 12,
        borderRadius: BorderRadius.circular(28),
        shadowColor: Colors.black26,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 38),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(28)),
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 8),
              Image.asset('assets/TruckSinghbgr.png', width: 110, height: 110),
              const SizedBox(height: 5),
              Text("welcome_back".tr(), style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Color(0xFF00796B), letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Text("sign_in_to_continue".tr(), style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.headlineMedium?.color, fontWeight: FontWeight.w400)),
              const SizedBox(height: 32),
              TextFormField(
                controller: _emailCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.emailAddress,
                decoration: _inputDecoration("email".tr(), Icons.email_outlined),
                validator: (val) => val == null || !val.contains('@') ? 'enter_valid_email'.tr() : null,
              ),
              const SizedBox(height: 22),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextFormField(
                  controller: _passCtrl,
                  enabled: !_loading,
                  obscureText: _obscureText,
                  style: const TextStyle(fontSize: 16),
                  decoration: _inputDecoration("password".tr(), Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off, color: Colors.teal.shade700),
                      onPressed: () => setState(() => _obscureText = !_obscureText),
                    ),
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return 'please_enter_password'.tr();
                    if (val.length < 8) return 'min_password'.tr();
                    return null;
                  },
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ResetPasswordRequestPage())),
                    child: Text("forgot_password".tr(), style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00796B),
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _loading ? null : _loginUser,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text("log_in".tr()),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _loading ? null : () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RoleSelectionPage())),
                child: Text("dont_have_account".tr(), style: TextStyle(color: Colors.teal.shade800, fontWeight: FontWeight.w600, fontSize: 16)),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: Divider(thickness: 1, color: Colors.teal.shade400, endIndent: 12)),
                Text("or_continue_with".tr(), style: TextStyle(color: Colors.teal.shade600, fontWeight: FontWeight.w500, fontSize: 14)),
                Expanded(child: Divider(thickness: 1, color: Colors.teal.shade400, indent: 12)),
              ]),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), side: BorderSide(color: Colors.grey.shade300, width: 1)),
                    onPressed: _loading ? null : () => _signInWithProvider(OAuthProvider.google),
                    child: const Icon(Icons.g_mobiledata, size: 32, color: Colors.red),
                  ),
                ),
                const SizedBox(width: 28),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _languageButton() => SafeArea(
    child: IconButton(icon: const Icon(Icons.translate_outlined, size: 28), onPressed: () => _showLanguageDialog(context)),
  );
}