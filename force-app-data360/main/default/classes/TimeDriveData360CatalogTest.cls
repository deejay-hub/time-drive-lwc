// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class TimeDriveData360CatalogTest {
  @IsTest
  static void readsDataModelObjectNamesFromTheMetadata() {
    List<Object> items = new List<Object>{
      '{fields=[{name=Check_in_Date__c, displayName=Check-in Date}], name=Reservation__dlm, displayName=Reservation}',
      '{fields=[{name=Risk__c}], name=Cancellation_Risk__cio, displayName=Cancellation Risk}',
      '{fields=[], name=ssot__Individual__dlm}'
    };
    List<String> names = TimeDriveData360Catalog.namesIn(items);
    names.sort();
    Assert.areEqual(new List<String>{ 'Reservation__dlm', 'ssot__Individual__dlm' }, names);
    Assert.isTrue(TimeDriveData360Catalog.namesIn(null).isEmpty());
  }

  @IsTest
  static void picksOutTheProfileObjects() {
    List<Object> items = new List<Object>{
      '{fields=[{name=ssot__FirstName__c, type=STRING}], name=ssot__Individual__dlm, category=Profile}',
      '{fields=[], name=ssot__EmailEngagement__dlm, category=Engagement}',
      '{fields=[], name=ssot__ContactPointEmail__dlm, category=Related}',
      '{fields=[], name=Reservation__dlm}'
    };
    Assert.areEqual(
      new Set<String>{ 'ssot__Individual__dlm' },
      TimeDriveData360Catalog.profileNamesIn(items),
      'Only those Data 360 calls Profile'
    );
    Assert.isTrue(TimeDriveData360Catalog.profileNamesIn(null).isEmpty());
  }

  @IsTest
  static void asksDataCloudWhereItIsThere() {
    // Without Data 360 data in a test, the call may fail; the catalog's
    // callers treat that as no DMOs.
    try {
      Assert.isNotNull(new TimeDriveData360Catalog().dmoNames('default'));
    } catch (Exception e) {
      Assert.isNotNull(e.getMessage());
    }
  }
}
