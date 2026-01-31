import '../models/problem.dart';

/// All available problems/levels in the game
class Problems {
  Problems._();

  static final List<Problem> all = [
    urlShortener,
    chatApp,
    twitterFeed,
    youtube,
    netflix,
    uber,
  ];

  /// Level 1: URL Shortener
  static final urlShortener = Problem(
    id: 'url_shortener',
    title: 'URL Shortener',
    description: 'Design a URL shortening service like bit.ly',
    scenario: '''
You're building a URL shortening service that:
• Takes long URLs and generates short, unique links
• Redirects users from short links to original URLs
• Tracks click analytics

The service must handle millions of daily users with low latency redirects.
''',
    constraints: const ProblemConstraints(
      dau: 10000000, // 10M DAU
      readWriteRatio: 100, // 100:1 read heavy (redirects vs creates)
      latencySlaMsP50: 20,
      latencySlaMsP95: 100,
      availabilityTarget: 0.999,
      budgetPerMonth: 5000,
      dataStorageGb: 50,
      regions: ['us-east-1'],
    ),
    hints: [
      'Redirects (reads) are much more frequent than URL creations (writes)',
      'Short URLs are read-heavy - perfect for caching',
      'Consider using a cache to reduce database load',
      'A single database might become a bottleneck at scale',
    ],
    optimalComponents: ['loadBalancer', 'appServer', 'cache', 'database'],
    optimalConnections: [
      ConnectionDefinition('loadBalancer', 'apiGateway'), // Optional but good
      ConnectionDefinition('loadBalancer', 'appServer'), // Direct or via API
      ConnectionDefinition('apiGateway', 'appServer'),
      ConnectionDefinition('appServer', 'database'),
      ConnectionDefinition('appServer', 'cache'),
    ],
    difficulty: 1,
    isUnlocked: true,
  );

  /// Level 2: Chat Application
  static final chatApp = Problem(
    id: 'chat_app',
    title: 'Chat Application',
    description: 'Design a real-time messaging system like WhatsApp',
    scenario: '''
Build a real-time chat application that:
• Delivers messages instantly between users
• Supports group chats with up to 256 members
• Shows online/offline status and typing indicators
• Stores message history

The system must feel instant while handling millions of concurrent connections.
''',
    constraints: const ProblemConstraints(
      dau: 50000000, // 50M DAU
      readWriteRatio: 5, // 5:1 (reading history vs sending)
      latencySlaMsP50: 50,
      latencySlaMsP95: 200,
      availabilityTarget: 0.9999,
      budgetPerMonth: 50000,
      dataStorageGb: 5000,
      regions: ['us-east-1', 'eu-west-1', 'ap-south-1'],
    ),
    hints: [
      'Real-time messaging requires persistent connections (WebSockets)',
      'Consider pub/sub for message fanout to group members',
      'Message delivery confirmation needs careful handling',
      'Users expect messages to persist even when offline',
    ],
    optimalComponents: [
      'loadBalancer',
      'apiGateway',
      'appServer',
      'cache',
      'database',
      'pubsub',
      'queue'
    ],
    difficulty: 2,
    isUnlocked: false,
  );

  /// Level 3: Twitter Feed
  static final twitterFeed = Problem(
    id: 'twitter_feed',
    title: 'Twitter Feed',
    description: 'Design a social media timeline like Twitter',
    scenario: '''
Create a social media feed system that:
• Shows personalized timelines for each user
• Handles celebrity accounts with millions of followers
• Supports real-time updates when new posts appear
• Allows likes, retweets, and replies

The challenge is fan-out: when someone posts, it must reach all followers.
''',
    constraints: const ProblemConstraints(
      dau: 100000000, // 100M DAU
      readWriteRatio: 1000, // Heavy read (timelines) vs write (posts)
      latencySlaMsP50: 100,
      latencySlaMsP95: 500,
      availabilityTarget: 0.999,
      budgetPerMonth: 100000,
      dataStorageGb: 10000,
      regions: ['us-east-1', 'us-west-2', 'eu-west-1', 'ap-south-1'],
    ),
    hints: [
      'Fan-out on write vs fan-out on read is a critical decision',
      'Celebrity tweets need special handling (millions of followers)',
      'Cache user timelines for fast reads',
      'Consider async processing for non-critical updates',
    ],
    optimalComponents: [
      'cdn',
      'loadBalancer',
      'apiGateway',
      'appServer',
      'cache',
      'database',
      'queue',
      'pubsub'
    ],
    difficulty: 3,
    isUnlocked: false,
  );

  /// Level 4: YouTube
  static final youtube = Problem(
    id: 'youtube',
    title: 'YouTube',
    description: 'Design a video streaming platform like YouTube',
    scenario: '''
Build a video streaming platform that:
• Allows users to upload videos of any size
• Transcodes videos into multiple resolutions
• Streams videos globally with minimal buffering
• Shows video recommendations and comments

Video delivery at scale requires careful architecture.
''',
    constraints: const ProblemConstraints(
      dau: 1000000000, // 1B DAU
      readWriteRatio: 10000, // Massive read (streaming) vs write (upload)
      latencySlaMsP50: 200,
      latencySlaMsP95: 1000,
      availabilityTarget: 0.9999,
      budgetPerMonth: 1000000,
      dataStorageGb: 1000000, // 1PB
      regions: ['us-east-1', 'us-west-2', 'eu-west-1', 'eu-central-1', 'ap-south-1', 'ap-northeast-1'],
    ),
    hints: [
      'CDN is essential for video delivery at global scale',
      'Video upload and transcoding should be async',
      'Separate metadata (fast) from video content (large)',
      'Consider blob storage for video files',
    ],
    optimalComponents: [
      'dns',
      'cdn',
      'loadBalancer',
      'apiGateway',
      'appServer',
      'worker',
      'cache',
      'database',
      'objectStore',
      'queue'
    ],
    difficulty: 4,
    isUnlocked: false,
  );

  /// Level 5: Netflix
  static final netflix = Problem(
    id: 'netflix',
    title: 'Netflix',
    description: 'Design a streaming service like Netflix',
    scenario: '''
Create a premium streaming service that:
• Delivers HD/4K video with zero buffering
• Provides personalized recommendations
• Handles global traffic with regional content
• Supports offline downloads

Quality of experience is paramount - users expect perfection.
''',
    constraints: const ProblemConstraints(
      dau: 200000000, // 200M DAU
      readWriteRatio: 100000, // Almost all reads
      latencySlaMsP50: 100,
      latencySlaMsP95: 300,
      availabilityTarget: 0.9999,
      budgetPerMonth: 5000000,
      dataStorageGb: 5000000, // 5PB
      regions: ['us-east-1', 'us-west-2', 'eu-west-1', 'eu-central-1', 'ap-south-1', 'ap-northeast-1', 'sa-east-1'],
    ),
    hints: [
      'Netflix uses Open Connect - custom CDN appliances',
      'Pre-position popular content in edge locations',
      'Adaptive bitrate streaming adjusts to network conditions',
      'Chaos engineering ensures resilience',
    ],
    optimalComponents: [
      'dns',
      'cdn',
      'loadBalancer',
      'apiGateway',
      'appServer',
      'serverless',
      'cache',
      'database',
      'objectStore',
      'stream'
    ],
    difficulty: 4,
    isUnlocked: false,
  );

  /// Level 6: Uber
  static final uber = Problem(
    id: 'uber',
    title: 'Uber',
    description: 'Design a ride-sharing platform like Uber',
    scenario: '''
Build a ride-sharing platform that:
• Matches riders with nearby drivers in real-time
• Tracks driver locations continuously
• Calculates dynamic pricing based on demand
• Handles payments and trip history

Location-based matching at massive scale is the challenge.
''',
    constraints: const ProblemConstraints(
      dau: 50000000, // 50M DAU
      readWriteRatio: 10, // Balanced (location updates are writes)
      latencySlaMsP50: 100,
      latencySlaMsP95: 300,
      availabilityTarget: 0.9999,
      budgetPerMonth: 500000,
      dataStorageGb: 50000,
      regions: ['us-east-1', 'us-west-2', 'eu-west-1', 'ap-south-1', 'ap-southeast-1'],
      customConstraints: {
        'locationUpdatesPerSecond': 1000000,
        'matchingLatencyMs': 500,
      },
    ),
    hints: [
      'Geospatial indexing is critical for nearby driver matching',
      'Driver location updates are high-frequency writes',
      'Consider event sourcing for trip history',
      'Surge pricing requires real-time demand analysis',
    ],
    optimalComponents: [
      'loadBalancer',
      'apiGateway',
      'appServer',
      'cache',
      'database',
      'queue',
      'stream',
      'pubsub'
    ],
    difficulty: 5,
    isUnlocked: false,
  );
}
