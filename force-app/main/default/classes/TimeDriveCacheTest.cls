/**
 * The cache partition is named by the package's own namespace: installed,
 * 'local' isn't the package's, so a partition named that way is never found
 * and nothing is kept, even with capacity allocated to it.
 */
@IsTest
private class TimeDriveCacheTest {
  @IsTest
  static void thePartitionIsThePackagesOwn() {
    if (String.isBlank(TimeDriveConfig.NAMESPACE)) {
      Assert.areEqual('local.TimeDrive', TimeDriveCache.PARTITION, 'unpackaged: this org\'s');
    } else {
      Assert.areEqual(TimeDriveConfig.NAMESPACE + '.TimeDrive', TimeDriveCache.PARTITION);
      Assert.isFalse(TimeDriveCache.PARTITION.startsWith('local.'), 'never local in a package');
    }
  }

  @IsTest
  static void keysFitTheCacheAndKeepTheirParts() {
    String a = TimeDriveCache.key(new List<String>{ 'ids', 'user one', null });
    String b = TimeDriveCache.key(new List<String>{ 'ids', 'user two', null });
    Assert.isTrue(a.length() <= 50, a);
    Assert.isTrue(Pattern.matches('[A-Za-z0-9]+', a), 'letters and digits only: ' + a);
    Assert.isTrue(a.startsWith('ids'), 'a readable prefix');
    Assert.areNotEqual(a, b, 'different parts, different keys');
  }
}
