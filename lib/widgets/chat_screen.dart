import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logistics_toolkit/providers/chat_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:logistics_toolkit/widgets/open_screen.dart';
import '../config/theme.dart';

class ChatScreen extends StatefulWidget {
  final Function(String screen) onNavigate;

  const ChatScreen({
    required this.onNavigate,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final stt.SpeechToText _speech;
  bool _listening = false;
  late String _language = context.locale.languageCode;

  bool _speechAvailable = false;
  String? _lastError;

  bool _hasUserTyped = false;

  // Animation controller for typing dots
  late AnimationController _typingController;
  late Animation<double> _typingAnimation;

  final List<Map<String, String>> _defaultPrompts = [
    {'text': 'I am a Driver', 'prompt': 'I am a driver'},
    {'text': 'I have Trucks', 'prompt': 'I have trucks'},
    {'text': 'Post Loads', 'prompt': 'I want to post loads'},
    {'text': 'Track Shipments', 'prompt': 'Show my active shipments'},
    {'text': 'Find Drivers', 'prompt': 'Show available drivers'},
    {'text': 'Truck Status', 'prompt': 'Check my trucks status'},
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();

    // Initialize typing animation
    _typingController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _typingAnimation = CurvedAnimation(
      parent: _typingController,
      curve: Curves.easeInOut,
    );

    _controller.addListener(() {
      if (_controller.text.isNotEmpty && !_hasUserTyped) {
        setState(() {
          _hasUserTyped = true;
        });
      } else if (_controller.text.isEmpty && _hasUserTyped) {
        setState(() {
          _hasUserTyped = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _typingController.dispose();
    _controller.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<bool> _requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<void> _ensurePermissionsAndInit() async {
    try {
      final granted = await _requestMicrophonePermission();
      if (!granted) {
        setState(() {
          _speechAvailable = false;
          _lastError = 'Microphone permission denied';
        });
        if (kDebugMode) debugPrint('ChatScreen: mic permission denied');
        return;
      }

      final available = await _speech.initialize(
        onStatus: (status) {
          if (kDebugMode) debugPrint('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            if (!mounted) return;
            setState(() => _listening = false);
          } else if (status == 'listening') {
            if (!mounted) return;
            setState(() => _listening = true);
          }
        },
        onError: (error) {
          if (kDebugMode) debugPrint('Speech error: $error');
          if (!mounted) return;
          setState(() {
            _lastError = error?.errorMsg ?? error.toString();
            _listening = false;
            _speechAvailable = false;
          });
        },
      );

      setState(() {
        _speechAvailable = available;
        if (!available)
          _lastError = 'Speech recognition not available on this device';
      });

      if (kDebugMode) debugPrint('Speech available: $available');
    } catch (e, st) {
      if (kDebugMode) debugPrint('Speech init exception: $e\n$st');
      setState(() {
        _speechAvailable = false;
        _lastError = e.toString();
      });
    }
  }

  Future<void> _toggleListen() async {
    if (!_speechAvailable) {
      await _ensurePermissionsAndInit();
      if (!_speechAvailable) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Microphone unavailable: ${_lastError ?? 'unknown'}',
              ),
            ),
          );
        }
        return;
      }
    }

    if (!_listening) {
      try {
        setState(() => _listening = true);
        await _speech.listen(
          onResult: (result) {
            if (!mounted) return;
            setState(() {
              _controller.text = result.recognizedWords;
              if (result.recognizedWords.isNotEmpty && !_hasUserTyped) {
                _hasUserTyped = true;
              }
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _controller.text.length),
              );
            });
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          localeId: _language == 'hi' ? 'hi_IN' : 'en_US',
          cancelOnError: true,
          partialResults: true,
        );
      } catch (e) {
        if (kDebugMode) debugPrint('Error starting listen: $e');
        setState(() {
          _listening = false;
          _lastError = e.toString();
        });
      }
    } else {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    }
  }

  Future<void> _onPromptSelected(String prompt) async {
    final provider = Provider.of<ChatProvider>(context, listen: false);

    setState(() {
      _controller.text = prompt;
      _hasUserTyped = true;
    });

    _controller.clear();

    await provider.send(
      prompt,
      onNavigate: (screen) {
        widget.onNavigate(screen);
      },
    );

    _scrollDown();
  }

  Future<void> _send() async {
    final txt = _controller.text.trim();
    if (txt.isEmpty) return;
    final provider = Provider.of<ChatProvider>(context, listen: false);
    _controller.clear();
    await provider.send(
      txt,
      onNavigate: (screen) {
        widget.onNavigate(screen);
      },
    );

    _scrollDown();
  }

  void _scrollDown() {
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _showDialogue() async {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text('chooseLanguage'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('English'.tr()),
              leading: const Icon(Icons.language),
              onTap: () {
                setState(() => _language = 'en');
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('हिंदी'),
              leading: const Icon(Icons.translate),
              onTap: () {
                setState(() => _language = 'hi');
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChips(bool isDark) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _defaultPrompts.map((prompt) {
        return GestureDetector(
          onTap: () => _onPromptSelected(prompt['prompt']!),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.teal.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Text(
              prompt['text']!,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.teal,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // TYPING INDICATOR WITH ANIMATED DOTS
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI Icon with animation
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.teal, AppColors.tealBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.teal.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.smart_toy_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 8),

          // Typing bubble with animated dots
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.6,
            ),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(
                color: AppColors.teal.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // AI thinking text
                    Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: AppColors.teal,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'AI is thinking',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.teal,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Animated dots
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAnimatedDot(0),
                    const SizedBox(width: 4),
                    _buildAnimatedDot(200),
                    const SizedBox(width: 4),
                    _buildAnimatedDot(400),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDot(int delay) {
    return AnimatedBuilder(
      animation: _typingController,
      builder: (context, child) {
        // Calculate opacity with delay for each dot
        double time = (_typingController.value * 1000 + delay) % 1000;
        double opacity = 0.3;

        if (time < 300) {
          opacity = 0.3 + (time / 300) * 0.7; // Fade in
        } else if (time < 600) {
          opacity = 1.0 - ((time - 300) / 300) * 0.7; // Fade out
        }

        return Opacity(
          opacity: opacity,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.teal,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ChatProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated AI Logo
              AnimatedBuilder(
                animation: _typingController,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.teal, AppColors.tealBlue],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.teal.withOpacity(
                              provider.isTyping ? 0.8 : 0.4),
                          blurRadius: provider.isTyping ? 12 : 8,
                          spreadRadius: provider.isTyping ? 2 : 1,
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        provider.isTyping ? Icons.auto_awesome : Icons.smart_toy,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Text(
                provider.isTyping ? 'AI Typing...' : 'AI Assistant',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              _buildIconButton(
                icon: provider.ttsEnabled ? Icons.volume_up : Icons.volume_off,
                isActive: provider.ttsEnabled,
                onTap: provider.toggleTts,
                tooltip: 'Text-to-Speech',
              ),
              const SizedBox(width: 8),
              _buildIconButton(
                icon: Icons.translate,
                onTap: _showDialogue,
                tooltip: 'Translate',
              ),
            ],
          ),
          backgroundColor: AppColors.teal,
          elevation: 2,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: isDark
                ? LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.darkBackground.withOpacity(0.8),
                AppColors.darkBackground,
              ],
            )
                : LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.background.withOpacity(0.9),
                AppColors.background,
              ],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: provider.messages.isEmpty && !provider.isTyping
                    ? SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Welcome section
                      Container(
                        margin: const EdgeInsets.only(bottom: 30),
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _typingController,
                              builder: (context, child) {
                                return Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: AppColors.teal
                                      .withOpacity(_typingController.value),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'How can I help you today?',
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? AppColors.darkText
                                    : AppColors.textColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'I\'m here to assist with your logistics needs',
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: isDark
                                    ? AppColors.darkText.withOpacity(0.6)
                                    : AppColors.textColor
                                    .withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (!_hasUserTyped) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Try asking:',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? AppColors.darkText
                                : AppColors.textColor.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildPromptChips(isDark),
                        const SizedBox(height: 30),
                        Text(
                          'Or type your question below',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: isDark
                                ? AppColors.darkText.withOpacity(0.5)
                                : AppColors.textColor.withOpacity(0.5),
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 100),
                        Text(
                          'Press send to get assistance',
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: isDark
                                ? AppColors.darkText.withOpacity(0.5)
                                : AppColors.textColor.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
                    : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.messages.length +
                      (provider.isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < provider.messages.length) {
                      final msg = provider.messages[index];
                      return _buildMessageBubble(msg, isDark);
                    } else {
                      // Show typing indicator
                      return _buildTypingIndicator();
                    }
                  },
                ),
              ),
              // Input Section
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: AppColors.orange.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    // Voice Input Button
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _listening
                            ? AppColors.orange.withOpacity(0.2)
                            : Colors.transparent,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _listening ? Icons.mic : Icons.mic_none,
                          color: _listening
                              ? AppColors.orange
                              : isDark
                              ? AppColors.darkText
                              : AppColors.textColor,
                          size: 22,
                        ),
                        onPressed: _toggleListen,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Text Field
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: isDark
                              ? AppColors.darkText
                              : AppColors.textColor,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          hintStyle: GoogleFonts.poppins(
                            color: isDark
                                ? AppColors.darkText.withOpacity(0.5)
                                : AppColors.textColor.withOpacity(0.5),
                          ),
                          border: InputBorder.none,
                          contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Send Button
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            AppColors.teal,
                            AppColors.tealBlue,
                          ],
                        ),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        onPressed: _send,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
        msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            // AI Icon with checkmark
            Stack(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.teal, AppColors.tealBlue],
                    ),
                  ),
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                // Small checkmark in corner
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.black : Colors.white,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 8,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: msg.isUser
                    ? LinearGradient(
                  colors: [
                    AppColors.orange,
                    AppColors.orange.withOpacity(0.8)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
                    : LinearGradient(
                  colors: [
                    isDark
                        ? AppColors.darkSurface.withOpacity(0.8)
                        : Colors.white,
                    isDark ? AppColors.darkSurface : Colors.white70,
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: msg.isUser
                      ? AppColors.orange.withOpacity(0.3)
                      : AppColors.teal.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.text,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      color: msg.isUser
                          ? Colors.white
                          : (isDark ? AppColors.darkText : AppColors.textColor),
                      height: 1.4,
                    ),
                  ),
                  if (msg.actionButtonScreen != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.teal, AppColors.tealBlue],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextButton(
                          onPressed: () {
                            openScreen(
                              msg.actionButtonScreen!,
                              context,
                              msg.actionParameters ?? {},
                            );
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            msg.actionButtonLabel ?? 'Open',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // AI timestamp
                  if (!msg.isUser) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Icon(
                        //   Icons.access_time,
                        //   size: 10,
                        //   color: AppColors.teal.withOpacity(0.5),
                        // ),
                        // const SizedBox(width: 4),
                        Text(
                          'AI',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            color: AppColors.teal.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (msg.isUser) ...[
            const SizedBox(width: 8),
            // User icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.orange, AppColors.orange.withOpacity(0.8)],
                ),
              ),
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    String? tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 20,
          color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
        ),
        onPressed: onTap,
        tooltip: tooltip,
        padding: const EdgeInsets.all(8),
      ),
    );
  }
}




//////
// class ChatScreen extends StatefulWidget {
//   final Function(String screen) onNavigate; // provide navigation callback
//
//   const ChatScreen({
//     required this.onNavigate,
//     super.key,
//   });
//
//   @override
//   State<ChatScreen> createState() => _ChatScreenState();
// }
//
// class _ChatScreenState extends State<ChatScreen> {
//   final TextEditingController _controller = TextEditingController();
//   final ScrollController _scroll = ScrollController();
//   late final stt.SpeechToText _speech;
//   bool _listening = false;
//   late String _language = context.locale.languageCode;
//
//   bool _speechAvailable = false;
//   String? _lastError;
//
//   // NEW: Track if user has started typing to hide default prompts
//   bool _hasUserTyped = false;
//
//   // Animatin
//
//   // NEW: Compact single-line prompts
//   final List<Map<String, String>> _defaultPrompts = [
//     {'text': 'I am a Driver', 'prompt': 'I am a driver'},
//     {'text': 'I have Trucks', 'prompt': 'I have trucks'},
//     {'text': 'Post Loads', 'prompt': 'I want to post loads'},
//     {'text': 'Track Shipments', 'prompt': 'Show my active shipments'},
//     {'text': 'Find Drivers', 'prompt': 'Show available drivers'},
//     {'text': 'Truck Status', 'prompt': 'Check my trucks status'},
//   ];
//
//   @override
//   void initState() {
//     super.initState();
//     _speech = stt.SpeechToText();
//
//     // NEW: Listen to text changes to hide default prompts
//     _controller.addListener(() {
//       if (_controller.text.isNotEmpty && !_hasUserTyped) {
//         setState(() {
//           _hasUserTyped = true;
//         });
//       } else if (_controller.text.isEmpty && _hasUserTyped) {
//         setState(() {
//           _hasUserTyped = false;
//         });
//       }
//     });
//   }
//
//   //addednew
//   @override
//   void dispose() {
//     _controller.dispose();
//     _speech.stop();
//     super.dispose();
//   }
//
//   Future<bool> _requestMicrophonePermission() async {
//     //request runtime permission using permission_handler
//     final status = await Permission.microphone.status;
//     if (status.isGranted) return true;
//     final result = await Permission.microphone.request();
//     return result.isGranted;
//   }
//
//   Future<void> _ensurePermissionsAndInit() async {
//     try {
//       final granted = await _requestMicrophonePermission();
//       if (!granted) {
//         setState(() {
//           _speechAvailable = false;
//           _lastError = 'Microphone permission denied';
//         });
//         if (kDebugMode) debugPrint('ChatScreen: mic permission denied');
//         return;
//       }
//
//       // Initialize speech with status and error callbacks
//       final available = await _speech.initialize(
//         onStatus: (status) {
//           if (kDebugMode) debugPrint('Speech status: $status');
//           if (status == 'done' || status == 'notListening') {
//             if (!mounted) return;
//             setState(() => _listening = false);
//           } else if (status == 'listening') {
//             if (!mounted) return;
//             setState(() => _listening = true);
//           }
//         },
//         onError: (error) {
//           if (kDebugMode) debugPrint('Speech error: $error');
//           if (!mounted) return;
//           setState(() {
//             _lastError = error?.errorMsg ?? error.toString();
//             _listening = false;
//             _speechAvailable = false;
//           });
//         },
//       );
//
//       setState(() {
//         _speechAvailable = available;
//         if (!available)
//           _lastError = 'Speech recognition not available on this device';
//       });
//
//       if (kDebugMode) debugPrint('Speech available: $available');
//     } catch (e, st) {
//       if (kDebugMode) debugPrint('Speech init exception: $e\n$st');
//       setState(() {
//         _speechAvailable = false;
//         _lastError = e.toString();
//       });
//     }
//   }
//
//   Future<void> _toggleListen() async {
//     // Ensure we have permission + initialized
//     if (!_speechAvailable) {
//       await _ensurePermissionsAndInit();
//       if (!_speechAvailable) {
//         // can't listen
//         if (mounted) {
//           ScaffoldMessenger.of(context).showSnackBar(
//             SnackBar(
//               content: Text(
//                 'Microphone unavailable: ${_lastError ?? 'unknown'}',
//               ),
//             ),
//           );
//         }
//         return;
//       }
//     }
//
//     if (!_listening) {
//       try {
//         setState(() => _listening = true);
//         await _speech.listen(
//           onResult: (result) {
//             if (!mounted) return;
//             setState(() {
//               _controller.text = result.recognizedWords;
//               // NEW: Mark as user typed when speech input starts
//               if (result.recognizedWords.isNotEmpty && !_hasUserTyped) {
//                 _hasUserTyped = true;
//               }
//               _controller.selection = TextSelection.fromPosition(
//                 TextPosition(offset: _controller.text.length),
//               );
//             });
//           },
//           listenFor: const Duration(seconds: 30),
//           pauseFor: const Duration(seconds: 3),
//           localeId: _language == 'hi' ? 'hi_IN' : 'en_US',
//           cancelOnError: true,
//           partialResults: true,
//         );
//       } catch (e) {
//         if (kDebugMode) debugPrint('Error starting listen: $e');
//         setState(() {
//           _listening = false;
//           _lastError = e.toString();
//         });
//       }
//     } else {
//       // stop listening
//       await _speech.stop();
//       if (mounted) setState(() => _listening = false);
//     }
//   }
//
//   // NEW: Handle prompt selection - auto send
//   Future<void> _onPromptSelected(String prompt) async {
//     final provider = Provider.of<ChatProvider>(context, listen: false);
//
//     // Set the text and mark as typed
//     setState(() {
//       _controller.text = prompt;
//       _hasUserTyped = true;
//     });
//
//     // Clear the controller immediately
//     _controller.clear();
//
//     // Send the prompt directly to AI
//     await provider.send(
//       prompt,
//       onNavigate: (screen) {
//         widget.onNavigate(screen);
//       },
//     );
//
//     _scrollDown();
//   }
//
//   Future<void> _send() async {
//     final txt = _controller.text.trim();
//     if (txt.isEmpty) return;
//     final provider = Provider.of<ChatProvider>(context, listen: false);
//     _controller.clear();
//     await provider.send(
//       txt,
//       onNavigate: (screen) {
//         widget.onNavigate(screen);
//       },
//     );
//
//     _scrollDown();
//   }
//
//   void _scrollDown(){
//     Future.delayed(const Duration(milliseconds: 200), (){
//       if(_scroll.hasClients){
//         _scroll.animateTo(
//             _scroll.position.maxScrollExtent,
//             duration: const Duration(milliseconds: 300),
//             curve: Curves.easeOut
//         );
//       }
//     });
//   }
//
//   Future<void> _showDialogue() async {
//     showDialog(
//       context: context,
//       builder: (BuildContext context) => AlertDialog(
//         title: Text('chooseLanguage'.tr()),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             ListTile(
//               title: Text('English'.tr()),
//               leading: const Icon(Icons.language),
//               onTap: () {
//                 setState(() => _language = 'en');
//                 Navigator.pop(context);
//               },
//             ),
//             ListTile(
//               title: Text('हिंदी'),
//               leading: const Icon(Icons.translate),
//               onTap: () {
//                 setState(() => _language = 'hi');
//                 Navigator.pop(context);
//               },
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   // NEW: Build compact prompt chips
//   Widget _buildPromptChips(bool isDark) {
//     return Wrap(
//       spacing: 8,
//       runSpacing: 8,
//       children: _defaultPrompts.map((prompt) {
//         return GestureDetector(
//           onTap: () => _onPromptSelected(prompt['prompt']!),
//           child: Container(
//             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//             decoration: BoxDecoration(
//               color: AppColors.teal.withOpacity(0.1),
//               borderRadius: BorderRadius.circular(16),
//               border: Border.all(
//                 color: AppColors.teal.withOpacity(0.3),
//                 width: 1,
//               ),
//             ),
//             child: Text(
//               prompt['text']!,
//               style: GoogleFonts.poppins(
//                 fontSize: 13,
//                 fontWeight: FontWeight.w500,
//                 color: AppColors.teal,
//               ),
//             ),
//           ),
//         );
//       }).toList(),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final provider = Provider.of<ChatProvider>(context);
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//
//     return SafeArea(
//       child: Scaffold(
//         appBar: AppBar(
//           title: Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               // Animated logo with glow effect
//               AnimatedContainer(
//                 duration: const Duration(milliseconds: 400),
//                 decoration: BoxDecoration(
//                   shape: BoxShape.circle,
//                   boxShadow: [
//                     BoxShadow(
//                       color: AppColors.teal.withOpacity(0.5),
//                       blurRadius: 8,
//                       spreadRadius: 2,
//                     ),
//                   ],
//                 ),
//                 child: Container(
//                   padding: const EdgeInsets.all(4),
//                   decoration: BoxDecoration(
//                     shape: BoxShape.circle,
//                     color: AppColors.teal.withOpacity(0.1),
//                   ),
//                   child: Image.asset('assets/chatbot.png', width: 32, height: 32),
//                 ),
//               ),
//               const SizedBox(width: 12),
//               Text(
//                 'AI Assistant',
//                 style: GoogleFonts.poppins(
//                   fontWeight: FontWeight.w600,
//                   fontSize: 20,
//                   color: Colors.white,
//                 ),
//               ),
//               const Spacer(),
//               // TTS Button
//               _buildIconButton(
//                 icon: provider.ttsEnabled ? Icons.volume_up : Icons.volume_off,
//                 isActive: provider.ttsEnabled,
//                 onTap: provider.toggleTts,
//                 tooltip: 'Text-to-Speech',
//               ),
//               const SizedBox(width: 8),
//               // Translate Button
//               _buildIconButton(
//                 icon: Icons.translate,
//                 onTap: _showDialogue,
//                 tooltip: 'Translate',
//               ),
//             ],
//           ),
//           backgroundColor: AppColors.teal,
//           elevation: 2,
//           shape: const RoundedRectangleBorder(
//             borderRadius: BorderRadius.vertical(
//               bottom: Radius.circular(16),
//             ),
//           ),
//         ),
//         body: Container(
//           decoration: BoxDecoration(
//             gradient: isDark
//                 ? LinearGradient(
//               begin: Alignment.topCenter,
//               end: Alignment.bottomCenter,
//               colors: [
//                 AppColors.darkBackground.withOpacity(0.8),
//                 AppColors.darkBackground,
//               ],
//             )
//                 : LinearGradient(
//               begin: Alignment.topCenter,
//               end: Alignment.bottomCenter,
//               colors: [
//                 AppColors.background.withOpacity(0.9),
//                 AppColors.background,
//               ],
//             ),
//           ),
//           child: Column(
//             children: [
//               Expanded(
//                 child: provider.messages.isEmpty
//                     ? SingleChildScrollView(
//                   padding: const EdgeInsets.all(20),
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       // Welcome section
//                       Container(
//                         margin: const EdgeInsets.only(bottom: 30),
//                         child: Column(
//                           children: [
//                             Icon(
//                               Icons.chat_bubble_outline,
//                               size: 64,
//                               color: AppColors.teal.withOpacity(0.5),
//                             ),
//                             const SizedBox(height: 16),
//                             Text(
//                               'How can I help you today?',
//                               style: GoogleFonts.poppins(
//                                 fontSize: 20,
//                                 fontWeight: FontWeight.w600,
//                                 color: isDark ? AppColors.darkText : AppColors.textColor,
//                               ),
//                               textAlign: TextAlign.center,
//                             ),
//                             const SizedBox(height: 8),
//                             Text(
//                               'I\'m here to assist with your logistics needs',
//                               style: GoogleFonts.poppins(
//                                 fontSize: 14,
//                                 color: isDark ? AppColors.darkText.withOpacity(0.6) : AppColors.textColor.withOpacity(0.5),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//
//                       // NEW: Show compact prompts only if user hasn't started typing
//                       if (!_hasUserTyped) ...[
//                         const SizedBox(height: 20),
//                         Text(
//                           'Try asking:',
//                           style: GoogleFonts.poppins(
//                             fontSize: 16,
//                             fontWeight: FontWeight.w500,
//                             color: isDark ? AppColors.darkText : AppColors.textColor.withOpacity(0.8),
//                           ),
//                         ),
//                         const SizedBox(height: 16),
//                         _buildPromptChips(isDark),
//                         const SizedBox(height: 30),
//                         Text(
//                           'Or type your question below',
//                           style: GoogleFonts.poppins(
//                             fontSize: 14,
//                             color: isDark ? AppColors.darkText.withOpacity(0.5) : AppColors.textColor.withOpacity(0.5),
//                           ),
//                         ),
//                       ] else ...[
//                         // Show typing indicator or empty space when user starts typing
//                         const SizedBox(height: 100),
//                         Text(
//                           'Press send to get assistance',
//                           style: GoogleFonts.poppins(
//                             fontSize: 14,
//                             color: isDark ? AppColors.darkText.withOpacity(0.5) : AppColors.textColor.withOpacity(0.5),
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 )
//                     : ListView.builder(
//                   controller: _scroll,
//                   padding: const EdgeInsets.all(16),
//                   itemCount: provider.messages.length,
//                   itemBuilder: (context, index) {
//                     final msg = provider.messages[index];
//                     return _buildMessageBubble(msg, isDark);
//                   },
//                 ),
//               ),
//               // Input Section
//               Container(
//                 margin: const EdgeInsets.all(16),
//                 padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//                 decoration: BoxDecoration(
//                   color: isDark ? AppColors.darkSurface : Colors.white,
//                   borderRadius: BorderRadius.circular(24),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.1),
//                       blurRadius: 8,
//                       offset: const Offset(0, 2),
//                     ),
//                   ],
//                   border: Border.all(
//                     color: AppColors.orange.withOpacity(0.3),
//                     width: 1,
//                   ),
//                 ),
//                 child: Row(
//                   children: [
//                     // Voice Input Button
//                     Container(
//                       decoration: BoxDecoration(
//                         shape: BoxShape.circle,
//                         color: _listening ? AppColors.orange.withOpacity(0.2) : Colors.transparent,
//                       ),
//                       child: IconButton(
//                         icon: Icon(
//                           _listening ? Icons.mic : Icons.mic_none,
//                           color: _listening ? AppColors.orange : isDark ? AppColors.darkText : AppColors.textColor,
//                           size: 22,
//                         ),
//                         onPressed: _toggleListen,
//                       ),
//                     ),
//                     const SizedBox(width: 4),
//                     // Text Field
//                     Expanded(
//                       child: TextField(
//                         controller: _controller,
//                         textInputAction: TextInputAction.send,
//                         onSubmitted: (_) => _send(),
//                         style: GoogleFonts.poppins(
//                           fontSize: 16,
//                           color: isDark ? AppColors.darkText : AppColors.textColor,
//                         ),
//                         decoration: InputDecoration(
//                           hintText: 'Type your message...',
//                           hintStyle: GoogleFonts.poppins(
//                             color: isDark ? AppColors.darkText.withOpacity(0.5) : AppColors.textColor.withOpacity(0.5),
//                           ),
//                           border: InputBorder.none,
//                           contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 4),
//                     // Send Button
//                     Container(
//                       decoration: BoxDecoration(
//                         shape: BoxShape.circle,
//                         gradient: LinearGradient(
//                           colors: [
//                             AppColors.teal,
//                             AppColors.tealBlue,
//                           ],
//                         ),
//                       ),
//                       child: IconButton(
//                         icon: const Icon(Icons.send, color: Colors.white, size: 20),
//                         onPressed: _send,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildMessageBubble(ChatMessage msg, bool isDark) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Row(
//         mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
//         children: [
//           if (!msg.isUser) ...[
//             Container(
//               width: 32,
//               height: 32,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 gradient: LinearGradient(
//                   colors: [AppColors.teal, AppColors.tealBlue],
//                 ),
//               ),
//               child: Icon(Icons.smart_toy, color: Colors.white, size: 16),
//             ),
//             const SizedBox(width: 8),
//           ],
//           Flexible(
//             child: Container(
//               padding: const EdgeInsets.all(14),
//               decoration: BoxDecoration(
//                 gradient: msg.isUser
//                     ? LinearGradient(
//                   colors: [AppColors.orange, AppColors.orange.withOpacity(0.8)],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 )
//                     : LinearGradient(
//                   colors: [
//                     isDark ? AppColors.darkSurface.withOpacity(0.8) : Colors.white,
//                     isDark ? AppColors.darkSurface : Colors.white70,
//                   ],
//                 ),
//                 borderRadius: BorderRadius.circular(18),
//                 boxShadow: [
//                   BoxShadow(
//                     color: Colors.black.withOpacity(0.1),
//                     blurRadius: 4,
//                     offset: const Offset(0, 2),
//                   ),
//                 ],
//                 border: Border.all(
//                   color: msg.isUser
//                       ? AppColors.orange.withOpacity(0.3)
//                       : AppColors.teal.withOpacity(0.3),
//                   width: 1,
//                 ),
//               ),
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     msg.text,
//                     style: GoogleFonts.poppins(
//                       fontSize: 15,
//                       color: msg.isUser ? Colors.white : (isDark ? AppColors.darkText : AppColors.textColor),
//                       height: 1.4,
//                     ),
//                   ),
//                   if (msg.actionButtonScreen != null) ...[
//                     const SizedBox(height: 8),
//                     Align(
//                       alignment: Alignment.centerRight,
//                       child: Container(
//                         decoration: BoxDecoration(
//                           gradient: LinearGradient(
//                             colors: [AppColors.teal, AppColors.tealBlue],
//                           ),
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         child: TextButton(
//                           onPressed: () {
//                             openScreen(
//                               msg.actionButtonScreen!,
//                               context,
//                               msg.actionParameters ?? {},
//                             );
//                           },
//                           style: TextButton.styleFrom(
//                             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
//                             shape: RoundedRectangleBorder(
//                               borderRadius: BorderRadius.circular(12),
//                             ),
//                           ),
//                           child: Text(
//                             msg.actionButtonLabel ?? 'Open',
//                             style: GoogleFonts.poppins(
//                               fontSize: 12,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.white,
//                             ),
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ),
//           if (msg.isUser) ...[
//             const SizedBox(width: 8),
//             Container(
//               width: 32,
//               height: 32,
//               decoration: BoxDecoration(
//                 shape: BoxShape.circle,
//                 gradient: LinearGradient(
//                   colors: [AppColors.orange, AppColors.orange.withOpacity(0.8)],
//                 ),
//               ),
//               child: Icon(Icons.person, color: Colors.white, size: 16),
//             ),
//           ],
//         ],
//       ),
//     );
//   }
//
//   Widget _buildIconButton({
//     required IconData icon,
//     required VoidCallback onTap,
//     bool isActive = false,
//     String? tooltip,
//   }) {
//     return Container(
//       decoration: BoxDecoration(
//         shape: BoxShape.circle,
//         color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
//         border: Border.all(
//           color: Colors.white.withOpacity(0.3),
//           width: 1,
//         ),
//       ),
//       child: IconButton(
//         icon: Icon(
//           icon,
//           size: 20,
//           color: isActive ? Colors.white : Colors.white.withOpacity(0.9),
//         ),
//         onPressed: onTap,
//         tooltip: tooltip,
//         padding: const EdgeInsets.all(6),
//       ),
//     );
//   }
// }
//
// Widget circleIcon({
//   required IconData icon,
//   required VoidCallback onTap,
//   Color iconColor = Colors.white,
//   Color iconBgColor = Colors.white24,
// }) {
//   return InkWell(
//     onTap: onTap,
//     borderRadius: BorderRadius.circular(30),
//     child: Container(
//       padding: const EdgeInsets.all(8),
//       decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
//       child: Icon(icon, color: iconColor, size: 20),
//     ),
//   );
// }