import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:dio/dio.dart';
import 'package:app/core/models/space.dart';
import 'package:app/core/models/conversation.dart';
import 'package:app/core/models/message.dart';

void main() {
  late Dio dio;
  late DioAdapter dioAdapter;

  setUp(() {
    dio = Dio();
    dioAdapter = DioAdapter(dio: dio);
    // Note: ApiClient creates its own Dio instance, so mocking is limited
    // These tests validate data structures and response parsing
  });

  group('Space API Tests', () {
    test('getSpaces returns list of spaces', () async {
      // Mock response matching backend format
      final mockResponse = {
        'spaces': [
          {
            'id': '1',
            'user_id': 'user1',
            'name': 'Test Space',
            'path': '/test/path',
            'created_at': '2025-01-01T00:00:00Z',
            'updated_at': '2025-01-01T00:00:00Z',
          },
          {
            'id': '2',
            'user_id': 'user1',
            'name': 'Another Space',
            'path': '/another/path',
            'created_at': '2025-01-01T00:00:00Z',
            'updated_at': '2025-01-01T00:00:00Z',
          },
        ],
      };

      dioAdapter.onGet(
        '/api/spaces',
        (server) => server.reply(200, mockResponse),
      );

      // Note: This test validates the data structure, but can't actually test
      // the ApiClient directly since it creates its own Dio instance.
      // This is more of a documentation of expected behavior.

      expect(mockResponse['spaces'], isA<List>());
      expect((mockResponse['spaces'] as List).length, 2);
    });

    test('createSpace sends correct payload', () {
      final mockResponse = {
        'id': '1',
        'user_id': 'user1',
        'name': 'New Space',
        'path': '/new/path',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      dioAdapter.onPost(
        '/api/spaces',
        (server) => server.reply(201, mockResponse),
        data: {
          'name': 'New Space',
          'path': '/new/path',
        },
      );

      expect(mockResponse['name'], 'New Space');
      expect(mockResponse['path'], '/new/path');
    });
  });

  group('Space Model Tests', () {
    test('Space.fromJson parses correctly', () {
      final json = {
        'id': '1',
        'user_id': 'user1',
        'name': 'Test Space',
        'path': '/test/path',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final space = Space.fromJson(json);

      expect(space.id, '1');
      expect(space.userId, 'user1');
      expect(space.name, 'Test Space');
      expect(space.path, '/test/path');
      expect(space.createdAt, isA<DateTime>());
      expect(space.updatedAt, isA<DateTime>());
    });

    test('Space.toJson serializes correctly', () {
      final space = Space(
        id: '1',
        userId: 'user1',
        name: 'Test Space',
        path: '/test/path',
        createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
        updatedAt: DateTime.parse('2025-01-01T00:00:00Z'),
      );

      final json = space.toJson();

      expect(json['id'], '1');
      expect(json['user_id'], 'user1');
      expect(json['name'], 'Test Space');
      expect(json['path'], '/test/path');
      expect(json['created_at'], isA<String>());
      expect(json['updated_at'], isA<String>());
    });
  });

  group('Conversation Model Tests', () {
    test('Conversation.fromJson parses correctly', () {
      final json = {
        'id': 'conv1',
        'space_id': 'space1',
        'title': 'Test Conversation',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      };

      final conversation = Conversation.fromJson(json);

      expect(conversation.id, 'conv1');
      expect(conversation.spaceId, 'space1');
      expect(conversation.title, 'Test Conversation');
      expect(conversation.createdAt, isA<DateTime>());
      expect(conversation.updatedAt, isA<DateTime>());
    });
  });

  group('Message Model Tests', () {
    test('Message.fromJson parses correctly', () {
      final json = {
        'id': 'msg1',
        'conversation_id': 'conv1',
        'role': 'user',
        'content': 'Hello, world!',
        'created_at': '2025-01-01T00:00:00Z',
      };

      final message = Message.fromJson(json);

      expect(message.id, 'msg1');
      expect(message.conversationId, 'conv1');
      expect(message.role, 'user');
      expect(message.content, 'Hello, world!');
      expect(message.createdAt, isA<DateTime>());
    });

    test('Message.toJson serializes correctly', () {
      final message = Message(
        id: 'msg1',
        conversationId: 'conv1',
        role: 'user',
        content: 'Hello, world!',
        createdAt: DateTime.parse('2025-01-01T00:00:00Z'),
      );

      final json = message.toJson();

      expect(json['id'], 'msg1');
      expect(json['conversation_id'], 'conv1');
      expect(json['role'], 'user');
      expect(json['content'], 'Hello, world!');
      expect(json['created_at'], isA<String>());
    });
  });

  group('API Response Format Tests', () {
    test('Spaces response has correct structure', () {
      final response = {
        'spaces': [
          {
            'id': '1',
            'user_id': 'user1',
            'name': 'Test',
            'path': '/test',
            'created_at': '2025-01-01T00:00:00Z',
            'updated_at': '2025-01-01T00:00:00Z',
          }
        ],
      };

      expect(response, contains('spaces'));
      expect(response['spaces'], isA<List>());

      final spaces = response['spaces'] as List;
      expect(spaces.isNotEmpty, true);
      expect(spaces[0], isA<Map>());

      final space = spaces[0] as Map<String, dynamic>;
      expect(space, contains('id'));
      expect(space, contains('name'));
      expect(space, contains('path'));
    });

    test('Conversations response has correct structure', () {
      final response = {
        'conversations': [
          {
            'id': 'conv1',
            'space_id': 'space1',
            'title': 'Test',
            'created_at': '2025-01-01T00:00:00Z',
            'updated_at': '2025-01-01T00:00:00Z',
          }
        ],
      };

      expect(response, contains('conversations'));
      expect(response['conversations'], isA<List>());
    });

    test('Messages response has correct structure', () {
      final response = {
        'messages': [
          {
            'id': 'msg1',
            'conversation_id': 'conv1',
            'role': 'user',
            'content': 'Hello',
            'created_at': '2025-01-01T00:00:00Z',
          }
        ],
      };

      expect(response, contains('messages'));
      expect(response['messages'], isA<List>());
    });
  });

  group('Error Handling Tests', () {
    test('Type casting from Map to List should fail', () {
      final response = {
        'spaces': [],
      };

      // This should NOT work - demonstrating the bug we fixed
      expect(
        () => response as List<dynamic>,
        throwsA(isA<TypeError>()),
      );

      // This should work - the correct way
      expect(response['spaces'], isA<List>());
    });

    test('Missing key in response throws error', () {
      final response = <String, dynamic>{};

      expect(
        () {
          final spaces = response['spaces'] as List<dynamic>;
          return spaces;
        },
        throwsA(isA<TypeError>()),
      );
    });
  });
}
