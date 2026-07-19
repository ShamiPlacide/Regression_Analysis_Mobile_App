import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "services/prediction_service.dart";

void main() => runApp(const ElectricityPredictorApp());

class ElectricityPredictorApp extends StatelessWidget {
  const ElectricityPredictorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Per-Capita Electricity Predictor",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2A7F62),
        useMaterial3: true,
      ),
      home: const PredictionPage(),
    );
  }
}

/// Declarative description of one input field — drives the UI, the validation,
/// and the request body, so nothing is duplicated across those three concerns.
class FeatureSpec {
  final String key; // exact JSON key the API expects
  final String label;
  final double min;
  final double max;
  final bool required;
  final String helper;
  const FeatureSpec(this.key, this.label, this.min, this.max, this.required, this.helper);
}

const List<FeatureSpec> kFeatures = [
  FeatureSpec("gdp", "GDP (current international \$)", 3.0e8, 2.8e13, true,
      "Required. Range: 3e8 – 2.8e13"),
  FeatureSpec("population", "Population", 60000, 1.5e9, true,
      "Required. Range: 60,000 – 1.5 billion"),
  FeatureSpec("energy_per_capita", "Energy per capita (kWh-equiv)", 100, 280000, true,
      "Required. Range: 100 – 280,000"),
  FeatureSpec("energy_per_gdp", "Energy intensity (energy / GDP)", 0.05, 11.0, true,
      "Required. Range: 0.05 – 11.0"),
  FeatureSpec("renewables_share_energy", "Renewables share (%)", 0, 100, false,
      "Optional. 0 – 100, leave blank if unknown"),
  FeatureSpec("fossil_share_energy", "Fossil share (%)", 0, 100, false,
      "Optional. 0 – 100, leave blank if unknown"),
  FeatureSpec("low_carbon_share_energy", "Low-carbon share (%)", 0, 100, false,
      "Optional. 0 – 100, leave blank if unknown"),
];

class PredictionPage extends StatefulWidget {
  const PredictionPage({super.key});
  @override
  State<PredictionPage> createState() => _PredictionPageState();
}

class _PredictionPageState extends State<PredictionPage> {
  final _formKey = GlobalKey<FormState>();
  final _service = PredictionService();
  final Map<String, TextEditingController> _controllers = {
    for (final f in kFeatures) f.key: TextEditingController(),
  };

  bool _loading = false;
  PredictionResult? _result; // set on success
  String? _serverError; // set on server/network failure

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Per-field client-side validation (runs before any request is sent).
  String? _validate(FeatureSpec f, String? raw) {
    final text = (raw ?? "").trim();
    if (text.isEmpty) {
      if (f.required) return "${f.label} is required";
      return null; // optional + blank -> valid (will be sent as null)
    }
    final value = double.tryParse(text);
    if (value == null) return "Enter a valid number";
    if (value < f.min || value > f.max) {
      return "Must be between ${_short(f.min)} and ${_short(f.max)}";
    }
    return null;
  }

  Future<void> _onPredict() async {
    // Clear any previous outcome, then run client validation.
    setState(() {
      _result = null;
      _serverError = null;
    });
    if (!_formKey.currentState!.validate()) {
      return; // inline field errors are now shown; nothing sent to the server
    }

    // Build the request body: optional + blank -> null (NOT 0).
    final Map<String, double?> body = {};
    for (final f in kFeatures) {
      final text = _controllers[f.key]!.text.trim();
      body[f.key] = text.isEmpty ? null : double.parse(text);
    }

    setState(() => _loading = true);
    try {
      final result = await _service.predict(body);
      setState(() => _result = result);
    } on PredictionException catch (e) {
      setState(() => _serverError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Predict Per-Capita Electricity"),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Estimate a country's electricity generated per person (kWh) "
                  "from its energy & economic profile.",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),

                // 7 input fields, generated from kFeatures.
                for (final f in kFeatures) ...[
                  TextFormField(
                    controller: _controllers[f.key],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r"[0-9.eE+-]")),
                    ],
                    decoration: InputDecoration(
                      labelText: f.label,
                      helperText: f.helper,
                      helperMaxLines: 2,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => _validate(f, v),
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                  const SizedBox(height: 16),
                ],

                const SizedBox(height: 4),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _onPredict,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bolt),
                    label: Text(_loading ? "Predicting..." : "Predict"),
                  ),
                ),
                const SizedBox(height: 20),

                _ResultArea(
                  loading: _loading,
                  result: _result,
                  serverError: _serverError,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The result display area — shows exactly one of: idle hint, success card,
/// or server/network error card. (Client-side field errors appear inline under
/// each field via the Form validators.)
class _ResultArea extends StatelessWidget {
  final bool loading;
  final PredictionResult? result;
  final String? serverError;
  const _ResultArea({required this.loading, this.result, this.serverError});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return const SizedBox.shrink(); // spinner already shown on the button
    }

    if (serverError != null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  serverError!,
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (result != null) {
      return Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Predicted per-capita electricity",
                  style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer)),
              const SizedBox(height: 8),
              Text(
                "${_formatNumber(result!.predictedKwh)} kWh per person",
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text("Model used: ${result!.modelUsed}",
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer)),
            ],
          ),
        ),
      );
    }

    // Idle state
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.outline),
            const SizedBox(width: 12),
            const Expanded(
              child: Text("Enter values above and tap Predict to see the estimate."),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1189.22" -> "1,189.2" (one decimal, thousands separators). No extra package.
String _formatNumber(double value) {
  final fixed = value.toStringAsFixed(1);
  final parts = fixed.split(".");
  final intPart = parts[0];
  final decPart = parts.length > 1 ? parts[1] : "0";
  final buffer = StringBuffer();
  for (int i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(",");
    buffer.write(intPart[i]);
  }
  return "$buffer.$decPart";
}

/// Compact range labels for validator messages, e.g. 2.8e13 -> "2.8e13".
String _short(double v) {
  if (v >= 1e6 || (v != 0 && v < 0.01)) {
    return v.toStringAsExponential(1).replaceAll("e+", "e");
  }
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toString();
}
