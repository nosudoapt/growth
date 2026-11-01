import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../core/db.dart';
import '../logic/spend_cap.dart';

enum LlmProvider { anthropic, openaiCompatible }

class LlmConfig {
  const LlmConfig({
    required this.provider,
    required this.baseUrl,
    required this.model,
    required this.apiKeySet,
    this.monthlyCapUsd = 5.0,
    this.pricePer1kUsd = 0.003,
  });

  final LlmProvider provider;
  final String baseUrl;
  final String model;
  final bool apiKeySet;
  final double monthlyCapUsd;
  final double pricePer1kUsd;
}

class SpendBlocked implements Exception {
  const SpendBlocked();
  @override
  String toString() =>
      'Monthly spend cap reached. LLM calls stop until the next month.';
}

class LlmError implements Exception {
  LlmError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Calm, user-facing copy for every failure mode.
String calmError(Object e) {
  if (e is SpendBlocked) return 'Spend cap reached — LLM features pause until next month. Your data is still saved locally.';
  if (e is LlmError) return e.message;
  return 'Something did not load. Everything is saved on your phone anyway.';
}

/// Calls the user's own LLM endpoint (Anthropic or any OpenAI-compatible
/// base URL). API key lives only in flutter_secure_storage, never in logs
/// or exports. HTTPS enforced. Every call times out and backs off once.
class LlmService {
  LlmService({http.Client? client, FlutterSecureStorage? secure})
      : _client = client ?? http.Client(),
        _secure = secure ?? const FlutterSecureStorage();

  final http.Client _client;
  final FlutterSecureStorage _secure;

  static const String _keyName = 'growth_llm_api_key';

  Future<void> saveKey(String key) => _secure.write(key: _keyName, value: key);
  Future<void> deleteKey() => _secure.delete(key: _keyName);
  Future<bool> hasKey() async => (await _secure.read(key: _keyName)) != null;

  Future<String?> readKey() async {
    try {
      return await _secure.read(key: _keyName);
    } catch (_) {
      return null;
    }
  }

  Future<LlmConfig> loadConfig() async {
    final raw = await Db.kvGet('llm_config');
    await Db.instance();
    final LlmProvider provider;
    String? baseUrl;
    String? model;
    double cap = 5.0;
    double price = 0.003;
    if (raw != null) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      provider = m['provider'] == 'anthropic'
          ? LlmProvider.anthropic
          : LlmProvider.openaiCompatible;
      baseUrl = m['base_url'] as String?;
      model = m['model'] as String?;
      cap = (m['monthly_cap_usd'] as num?)?.toDouble() ?? 5.0;
      price = (m['price_per_1k_usd'] as num?)?.toDouble() ?? 0.003;
    } else {
      provider = LlmProvider.anthropic;
    }
    return LlmConfig(
      provider: provider,
      baseUrl: baseUrl ?? _defaultBase(provider),
      model: model ?? _defaultModel(provider),
      apiKeySet: await hasKey(),
      monthlyCapUsd: cap,
      pricePer1kUsd: price,
    );
  }

  Future<void> saveConfig(LlmConfig c) => Db.kvSet('llm_config',
      jsonEncode({'provider': c.provider.name, 'base_url': c.baseUrl, 'model': c.model, 'monthly_cap_usd': c.monthlyCapUsd, 'price_per_1k_usd': c.pricePer1kUsd}));

  static String _defaultBase(LlmProvider p) => p == LlmProvider.anthropic
      ? 'https://api.anthropic.com'
      : 'https://api.openai.com';

  static String _defaultModel(LlmProvider p) => p == LlmProvider.anthropic
      ? 'claude-sonnet-4-5'
      : 'gpt-4o-mini';

  // ---- Spend accounting ---------------------------------------------

  Future<double> monthUsageUsd() async {
    final m = SpendCap.monthKey(DateTime.now());
    final raw = await Db.kvGet('token_usage_current');
    if (raw == null) return 0.0;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    if (j['month'] != m) return 0.0;
    return (j['usd'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> monthUsageTokens() async {
    final raw = await Db.kvGet('token_usage_current');
    if (raw == null) return 0;
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return (j['tokens'] as num?)?.toInt() ?? 0;
  }

  Future<void> _addUsage(LlmConfig c, int tokens) async {
    final m = SpendCap.monthKey(DateTime.now());
    final raw = await Db.kvGet('token_usage_current');
    var prevUsd = 0.0;
    var prevTokens = 0;
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['month'] == m) {
        prevUsd = (j['usd'] as num?)?.toDouble() ?? 0.0;
        prevTokens = (j['tokens'] as num?)?.toInt() ?? 0;
      }
    }
    final tokens2 = prevTokens + tokens;
    final usd = SpendCap.estimateUsd(tokens2, c.pricePer1kUsd);
    await Db.kvSet(
        'token_usage_current', jsonEncode({'month': m, 'tokens': tokens2, 'usd': usd}));
  }

  // ---- Core call ------------------------------------------------------

  /// Runs `prompt`, parses the reply through `parse`, retries once on
  /// transient failure, and blocks past the monthly spend cap.
  /// Throws SpendBlocked / LlmError. Never logs the key.
  Future<T> complete<T>({
    required LlmConfig config,
    required String prompt,
    required String system,
    required T Function(String reply) parse,
    int maxOutputTokens = 700,
    Duration timeout = const Duration(seconds: 40),
  }) async {
    final key = await readKey();
    if (key == null || key.isEmpty) {
      throw LlmError('No API key set. Add one in Settings to use this feature.');
    }
    final tokens =
        SpendCap.estimateTokens(prompt, system, maxOutputTokens);
    final callUsd = SpendCap.estimateUsd(tokens, config.pricePer1kUsd);
    final usedUsd = await monthUsageUsd();
    if (SpendCap.willExceed(
        currentMonthUsd: usedUsd,
        callEstimateUsd: callUsd,
        monthlyCapUsd: config.monthlyCapUsd)) {
      throw const SpendBlocked();
    }

    var lastException = '';
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        // Calm backoff: one short wait, not a retry storm.
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      try {
        final reply = await _rawCall(
            config: config, system: system, prompt: prompt, key: key, maxOutputTokens: maxOutputTokens, timeout: timeout);
        await _addUsage(config, tokens);
        try {
          return parse(reply);
        } catch (_) {
          throw LlmError('The reply could not be used — kept the last good version.');
        }
      } on LlmError {
        rethrow;
      } catch (e) {
        lastException = e.toString();
      }
    }
    throw LlmError(
        'Could not reach the model just now. ${_shortReason(lastException)}');
  }

  static String _shortReason(String s) {
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'It took too long.';
    }
    if (s.contains('401') || s.contains('403')) {
      return 'The key was rejected.';
    }
    if (s.contains('429')) {
      return 'The provider was busy.';
    }
    return 'No clear reason.';
  }

  Future<String> _rawCall({
    required LlmConfig config,
    required String system,
    required String prompt,
    required String key,
    required int maxOutputTokens,
    required Duration timeout,
  }) async {
    final Uri uri;
    final Map<String, String> headers;
    final Map<String, dynamic> body;

    if (config.provider == LlmProvider.anthropic) {
      uri = Uri.parse('${_base(config.baseUrl)}/v1/messages');
      headers = {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': '2023-06-01',
      };
      body = {
        'model': config.model,
        'max_tokens': maxOutputTokens,
        'system': system,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      };
    } else {
      uri = Uri.parse('${_base(config.baseUrl)}/v1/chat/completions');
      headers = {
        'content-type': 'application/json',
        'authorization': 'Bearer $key',
      };
      body = {
        'model': config.model,
        'max_tokens': maxOutputTokens,
        'temperature': 0.7,
        'messages': [
          {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ],
      };
    }

    final resp = await _client
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      String? text;
      if (config.provider == LlmProvider.anthropic) {
        final content = data['content'] as List?;
        if (content != null && content.isNotEmpty) {
          final first = content.first as Map<String, dynamic>;
          text = first['text'] as String?;
        }
      } else {
        final choices = data['choices'] as List?;
        if (choices != null && choices.isNotEmpty) {
          final c = choices.first as Map<String, dynamic>;
          final msg = c['message'] as Map<String, dynamic>?;
          text = msg?['content'] as String?;
        }
      }
      if (text == null || text.isEmpty) {
        throw LlmError('The reply was empty.');
      }
      return text;
    }
    throw LlmError('HTTP ${resp.statusCode}');
  }

  static String _base(String url) {
    var u = url.trim();
    if (u.startsWith('http://')) {
      throw LlmError('Only HTTPS endpoints are allowed.');
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    if (!u.startsWith('https://')) {
      throw LlmError('The base URL must start with https://');
    }
    if (configHasV1Suffix(u)) return u.substring(0, u.length - 3);
    return u;
  }

  static bool configHasV1Suffix(String u) => u.endsWith('/v1');
}
