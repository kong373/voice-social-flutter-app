import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:voice_social_app/core/media/media_identity.dart';
import 'package:voice_social_app/core/network/api_client.dart';

class TestMediaIdentity extends ChangeNotifier {
  int user = 1;
  int generation = 1;
  String token = 'Bearer contract-A-old';
  void refreshToken() {
    token = 'Bearer contract-refreshed';
    notifyListeners();
  }

  void change(int next) {
    user = next;
    generation++;
    token = 'Bearer contract-$next';
    notifyListeners();
  }

  MediaIdentityScope scope() => MediaIdentityScope(
    currentUserId: () => user,
    identityGeneration: () => generation,
    changes: this,
  );
}

class MediaFakeHttp implements HttpClient {
  MediaFakeHttp(this.respond);
  final FutureOr<HttpClientResponse> Function(MediaFakeRequest) respond;
  final requests = <MediaFakeRequest>[];
  Future<void> Function(int)? beforeOpen;
  int opens = 0;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    await beforeOpen?.call(++opens);
    final request = MediaFakeRequest(method, url, respond);
    requests.add(request);
    return request;
  }

  ApiClient api(
    TestMediaIdentity identity, {
    Future<bool> Function()? refresh,
    int maximumResponseBytes = 2 * 1024 * 1024,
  }) => ApiClient(
    baseUri: Uri.parse('https://configured.backend.test'),
    clientType: 'test',
    clientInnerVersion: '1',
    authorizationProvider: () => identity.token,
    unauthorizedRecovery: refresh,
    httpClient: this,
    maximumResponseBytes: maximumResponseBytes,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MediaFakeRequest implements HttpClientRequest {
  MediaFakeRequest(this.method, this.uri, this.respond);
  @override
  final String method;
  @override
  final Uri uri;
  final FutureOr<HttpClientResponse> Function(MediaFakeRequest) respond;
  @override
  final headers = MediaFakeHeaders();
  final body = <int>[];
  bool aborted = false;
  int closes = 0;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  void add(List<int> data) => body.addAll(data);
  @override
  void write(Object? value) => add(utf8.encode(value.toString()));
  @override
  Future<void> flush() async {}
  @override
  Future<HttpClientResponse> close() async {
    closes++;
    return respond(this);
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborted = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MediaFakeHeaders implements HttpHeaders {
  final values = <String, List<String>>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = [value.toString()];
  }

  @override
  void removeAll(String name) => values.remove(name.toLowerCase());
  @override
  String? value(String name) => values[name.toLowerCase()]?.join(',');
  @override
  void forEach(void Function(String, List<String>) action) =>
      values.forEach(action);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MediaFakeResponse extends Stream<List<int>>
    implements HttpClientResponse {
  MediaFakeResponse(
    this.statusCode,
    this.stream, {
    this.contentLength = -1,
    String? type,
  }) {
    if (type != null) headers.set('Content-Type', type);
  }
  factory MediaFakeResponse.json(
    Object? data, {
    int status = 200,
    int code = 200,
  }) => MediaFakeResponse(
    status,
    Stream.value(
      utf8.encode(
        jsonEncode({'code': code, 'message': 'contract', 'data': data}),
      ),
    ),
  );
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final headers = MediaFakeHeaders();
  final Stream<List<int>> stream;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
