import 'dart:convert';

class SimpleJson {
  static Map<String, dynamic> textToDictionary(String text) {
    return jsonDecode(text);
    //return new Reader (text).ToDictionary ();
  }

  static String serialize(Map<String, dynamic> dict) {
    return jsonEncode(dict);
  }
}
