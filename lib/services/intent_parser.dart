import 'dart:convert';

class BotAction {
  final String action;
  final Map<String, dynamic> parameters;
  final String reply;
  final String language;

  BotAction({
    required this.action,
    required this.parameters,
    required this.reply,
    required this.language
  });

}

BotAction parseBotOutput(String raw){
  //try to extract first JSON object from raw text
  final trimmed = raw.trim();

  try{
    final idxStart = trimmed.indexOf('{');
    final idxEnd = trimmed.lastIndexOf('}');
    if(idxStart != -1 &&  idxEnd != -1 && idxEnd > idxStart){
      final jsonText = trimmed.substring(idxStart,idxEnd+1);
      final map = jsonDecode(jsonText) as Map<String, dynamic>;

      return BotAction(
          action: map['action']?.toString() ?? 'unknown',
          parameters: Map<String,dynamic>.from(map['parameters'] ?? {}),
          reply: map['reply']?.toString() ?? '',
          language: map['language'].toString() ?? 'en'
      );

    }

  }catch(e){
    print(e);
  }
  
  return BotAction(action: 'unknown', parameters: {}, reply: "Sorry,I didn't understand.", language: 'en');
}