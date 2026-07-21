// ---------------------------------------------------------------------------
// API service — this is THE file that talks to the FastAPI backend.
// (For the video demo: "here is the Flutter code where I call the API.")
//
// Keeping all networking here (not in the widget) means the UI just calls
// PredictionService().predict(...) and reacts to the result.
// ---------------------------------------------------------------------------
import "dart:async";
import "dart:convert";

import "package:http/http.dart" as http;

import "../config.dart";

/// Successful prediction returned by POST /predict.
class PredictionResult {
  final double predictedKwh;
  final String modelUsed;
  const PredictionResult(this.predictedKwh, this.modelUsed);
}

/// A user-readable error (bad input rejected by the server, or a network problem).
/// The UI shows [message] directly — it is always safe/clean text, never raw JSON.
class PredictionException implements Exception {
  final String message;
  const PredictionException(this.message);
  @override
  String toString() => message;
}

class PredictionService {
  final http.Client _client;
  PredictionService([http.Client? client]) : _client = client ?? http.Client();

  /// Calls POST {kApiBaseUrl}/predict.
  ///
  /// [features] must contain the 7 keys the API expects. The three energy-mix
  /// shares may be `null` (meaning "unknown") — they are sent as JSON null, not 0.
  Future<PredictionResult> predict(Map<String, double?> features) async {
    final uri = Uri.parse("$kApiBaseUrl/predict");
    try {
      final response = await _client
          .post(
            uri,
            headers: const {"Content-Type": "application/json"},
            body: jsonEncode(features),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final value = (data["predicted_per_capita_electricity_kwh"] as num).toDouble();
        final model = (data["model_used"] as String?) ?? "unknown";
        return PredictionResult(value, model);
      }

      if (response.statusCode == 422) {
        // FastAPI/Pydantic validation error -> turn it into readable text.
        throw PredictionException(_parseValidationError(response.body));
      }

      if (response.statusCode == 503) {
        throw const PredictionException(
            "The model is not loaded on the server yet. Please try again shortly.");
      }

      throw PredictionException(
          "Server returned an unexpected error (HTTP ${response.statusCode}).");
    } on PredictionException {
      rethrow; // already a clean, user-facing message
    } on TimeoutException {
      throw PredictionException(
          "The server took too long to respond (>20s).\nURL: $kApiBaseUrl\n"
          "If it's the first call, the API may be waking from sleep — try again.");
    } catch (e) {
      // SocketException (mobile) or http.ClientException (web) etc. land here.
      // The URL + technical detail below make the real cause visible on screen.
      throw PredictionException(
          "Couldn't reach the API.\nURL tried: $kApiBaseUrl\nTechnical detail: $e");
    }
  }

  /// Converts a Pydantic 422 body into "field: reason" lines.
  /// Body shape: {"detail": [{"loc": ["body","gdp"], "msg": "Field required", ...}, ...]}
  String _parseValidationError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final detail = decoded["detail"];
      if (detail is List) {
        final lines = detail.map((item) {
          final loc = (item["loc"] as List)
              .where((part) => part != "body")
              .join(".");
          final msg = item["msg"] ?? "invalid value";
          return loc.isEmpty ? "$msg" : "$loc: $msg";
        }).toList();
        return "The server rejected the input:\n${lines.join("\n")}";
      }
      return detail?.toString() ?? "The server rejected the input (422).";
    } catch (_) {
      return "The server rejected the input (422).";
    }
  }
}
