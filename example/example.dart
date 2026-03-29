import 'package:flutter/material.dart';
import 'package:zero_cached_image/zero_cached_image.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('zero_cached_image')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic usage
            ZeroCachedImage(
              imageUrl: 'https://picsum.photos/400/300',
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 16),

            // With placeholder and error handling
            ZeroCachedImage(
              imageUrl: 'https://picsum.photos/400/301',
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 300),
              placeholder: (context, url) => Container(
                color: Colors.grey[300],
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[300],
                child: const Center(child: Icon(Icons.error)),
              ),
            ),
            const SizedBox(height: 16),

            // As ImageProvider in a CircleAvatar
            const CircleAvatar(
              radius: 40,
              backgroundImage: ZeroCachedImageProvider(
                'https://picsum.photos/200/200',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
