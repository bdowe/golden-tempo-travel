import 'dart:convert';
import '../models/local_recommendation.dart';
import '../models/local_guide.dart';
import 'api_client.dart';

/// Wraps the local-sourced content endpoints. The /local/* reads are public; the
/// /admin/local/* curation calls require an admin bearer token (enforced
/// server-side). Bearer token is sent whenever present, matching the other
/// services.
class LocalApiService {
  final ApiClient apiClient;

  LocalApiService(this.apiClient);

  Map<String, String> _headers() {
    final h = <String, String>{'Accept': 'application/json'};
    final token = apiClient.authToken;
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  // --- public reads ----------------------------------------------------------

  /// Published local recommendations for [city], optionally filtered by category.
  Future<List<LocalRecommendation>> searchRecommendations(
    String city, {
    String? category,
  }) async {
    final uri = Uri.parse('${apiClient.baseUrl}/local/recommendations').replace(
      queryParameters: {
        'city': city,
        if (category != null && category.isNotEmpty) 'category': category,
      },
    );
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['recommendations'] as List<dynamic>? ?? []);
      return list
          .map((e) => LocalRecommendation.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to load local recommendations: ${res.body}',
      endpoint: 'local/recommendations',
    );
  }

  /// Published narrative guides for [city].
  Future<List<LocalGuide>> guides(String city) async {
    final uri = Uri.parse('${apiClient.baseUrl}/local/guides')
        .replace(queryParameters: {'city': city});
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['guides'] as List<dynamic>? ?? []);
      return list
          .map((e) => LocalGuide.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to load local guides: ${res.body}',
      endpoint: 'local/guides',
    );
  }

  /// One published guide by [id], plus its ordered pins. The detail endpoint's
  /// guide row omits the source attribution join, so callers that came from the
  /// list should keep the list row's source fields for display.
  Future<({LocalGuide guide, List<LocalRecommendation> recommendations})>
      guideById(String id) async {
    final uri = Uri.parse('${apiClient.baseUrl}/local/guides/$id');
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final recs = (body['recommendations'] as List<dynamic>? ?? [])
          .map((e) => LocalRecommendation.fromJson(e as Map<String, dynamic>))
          .toList();
      return (
        guide: LocalGuide.fromJson(body['guide'] as Map<String, dynamic>),
        recommendations: recs,
      );
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to load guide: ${res.body}',
      endpoint: 'local/guides/$id',
    );
  }

  // --- admin / curation ------------------------------------------------------

  /// Lists the local sources (people) the curator can attribute content to.
  Future<List<Map<String, dynamic>>> listSources() async {
    final uri = Uri.parse('${apiClient.baseUrl}/admin/local/sources');
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to list sources: ${res.body}',
      endpoint: 'admin/local/sources',
    );
  }

  /// Creates a local source (person) and returns the created row.
  Future<Map<String, dynamic>> createSource(
      Map<String, dynamic> fields) async {
    final uri = Uri.parse('${apiClient.baseUrl}/admin/local/sources');
    final res = await apiClient.httpClient.post(
      uri,
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode(fields),
    );
    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to create source: ${res.body}',
      endpoint: 'admin/local/sources',
    );
  }

  /// Runs AI extraction over raw research text for a source + city, returning the
  /// ingest summary ({recommendations, verified, unverified, guide_id?}).
  Future<Map<String, dynamic>> ingest({
    required String sourceId,
    required String city,
    required String kind,
    required String rawText,
  }) async {
    final uri = Uri.parse('${apiClient.baseUrl}/admin/local/ingest');
    final res = await apiClient.httpClient.post(
      uri,
      headers: {..._headers(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'source_id': sourceId,
        'city': city,
        'kind': kind,
        'raw_text': rawText,
      }),
    );
    if (res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Ingest failed: ${res.body}',
      endpoint: 'admin/local/ingest',
    );
  }

  /// Lists recommendations by status (default 'draft') for the review queue.
  Future<List<Map<String, dynamic>>> listByStatus(String status) async {
    final uri = Uri.parse('${apiClient.baseUrl}/admin/local/recommendations')
        .replace(queryParameters: {'status': status});
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to list recommendations: ${res.body}',
      endpoint: 'admin/local/recommendations',
    );
  }

  /// Publishes a draft recommendation. Throws with the server message (e.g. the
  /// "no coordinates" gate) on failure.
  Future<void> publish(String id) async {
    final uri = Uri.parse(
        '${apiClient.baseUrl}/admin/local/recommendations/$id/publish');
    final res = await apiClient.httpClient.post(uri, headers: _headers());
    if (res.statusCode != 200) {
      throw ApiException(
        statusCode: res.statusCode,
        message: _extractMessage(res.body),
        endpoint: 'admin/local/recommendations/publish',
      );
    }
  }

  /// Coverage: per-city published/draft/archived counts.
  Future<List<Map<String, dynamic>>> coverage() async {
    final uri = Uri.parse('${apiClient.baseUrl}/admin/local/coverage');
    final res = await apiClient.httpClient.get(uri, headers: _headers());
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list.cast<Map<String, dynamic>>();
    }
    throw ApiException(
      statusCode: res.statusCode,
      message: 'Failed to load coverage: ${res.body}',
      endpoint: 'admin/local/coverage',
    );
  }

  String _extractMessage(String body) {
    try {
      final m = jsonDecode(body) as Map<String, dynamic>;
      return (m['message'] as String?) ?? body;
    } catch (_) {
      return body;
    }
  }
}
