/**
 * What the timeline keeps between requests, in Platform Cache's org cache
 * (the Time Drive partition): lookups whose answers rarely change, so
 * each page doesn't repeat them. With no capacity allocated, or no
 * partition, nothing is kept and every lookup runs as before.
 */
public with sharing class TimeDriveCache {
  public static final String PARTITION = 'local.TimeDrive';
  // How long an entry is kept, in seconds.
  public static final Integer TTL = 900;

  // Tests stand in for Platform Cache here.
  @TestVisible
  private static Map<String, Object> testStore;

  /**
   * A cached value by key.
   *
   * @param key the cache key
   * @return the value, or null when none is kept
   */
  public static Object get(String key) {
    if (testStore != null) {
      return testStore.get(key);
    }
    try {
      return Cache.Org.getPartition(PARTITION).get(key);
    } catch (Exception e) {
      return null;
    }
  }

  /**
   * Keeps a value for the cache's time to live; if the cache cannot take it, nothing is kept.
   *
   * @param key the cache key
   * @param value the value to keep
   */
  public static void put(String key, Object value) {
    if (testStore != null) {
      testStore.put(key, value);
      return;
    }
    try {
      Cache.Org.getPartition(PARTITION).put(key, value, TTL);
    } catch (Exception e) {
      // No partition, or no room: not kept.
      System.debug(LoggingLevel.FINE, 'Time Drive cache: not kept. ' + e.getMessage());
    }
  }

  /**
   * A cache key from parts: letters and digits only, as the cache needs.
   *
   * @param parts the parts to build the key from
   * @return the key
   */
  public static String key(List<String> parts) {
    List<String> named = new List<String>();
    for (String part : parts) {
      named.add(part == null ? '' : part);
    }
    String joined = String.join(named, '|');
    String hash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(joined)));
    // A readable prefix, then the hash so any parts fit the 50-character limit.
    return (parts[0].replaceAll('[^A-Za-z0-9]', '') + hash).left(50);
  }
}
