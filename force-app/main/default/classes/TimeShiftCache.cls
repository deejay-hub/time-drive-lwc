/**
 * What the timeline keeps between requests, in Platform Cache's org cache
 * (the Time Trail partition): lookups whose answers rarely change, so
 * each page doesn't repeat them. With no capacity allocated, or no
 * partition, nothing is kept and every lookup runs as before.
 */
public with sharing class TimeShiftCache {
  public static final String PARTITION = 'local.TimeShift';
  // How long an entry is kept, in seconds.
  public static final Integer TTL = 900;

  // Tests stand in for Platform Cache here.
  @TestVisible
  private static Map<String, Object> testStore;

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

  public static void put(String key, Object value) {
    if (testStore != null) {
      testStore.put(key, value);
      return;
    }
    try {
      Cache.Org.getPartition(PARTITION).put(key, value, TTL);
    } catch (Exception e) {
      // No partition, or no room: not kept.
      System.debug(LoggingLevel.FINE, 'Time Trail cache: not kept. ' + e.getMessage());
    }
  }

  /** A cache key from parts: letters and digits only, as the cache needs. */
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
