import 'package:flutter/material.dart';

class FloatingChatControl extends StatelessWidget {
  final VoidCallback onOpenChat;
  final bool listening;

  const FloatingChatControl({
    required this.onOpenChat,
    this.listening = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100, right: 13),
           child:
           //Column(
          //   mainAxisSize: MainAxisSize.min,
          //   children: [
              //chat button - simple + light animation
             FloatingActionButton(
                  mini: true,
                  heroTag: 'chat_return',
                  onPressed: onOpenChat,
                  backgroundColor: Colors.black87,
                  child: Padding(padding: EdgeInsets.all(1) ,child:  Image.asset('assets/chatbot.png' ))
                ),
              ),

              // const SizedBox(height: 8),

              // AnimatedContainer(
              //   duration: const Duration(milliseconds: 300),
              //   curve: Curves.easeInOut,
              //   decoration: BoxDecoration(
              //     shape: BoxShape.circle,
              //     boxShadow: listening
              //         ? [
              //             BoxShadow(
              //               color: Colors.red.withOpacity(0.6),
              //               blurRadius: 18,
              //               spreadRadius: 3,
              //             ),
              //           ]
              //         : [],
              //   ),
              //   child: FloatingActionButton(
              //     mini: true,
              //     heroTag: 'chat_mic',
              //     onPressed: onMicTap,
              //     backgroundColor: listening ? Colors.red : Colors.black87,
              //     child: Icon(
              //       listening ? Icons.mic : Icons.mic_none,
              //       color: Colors.white,
              //     ),
              //   ),
              // ),
          //   ],
          // ),
        ),
    );
  }
}
