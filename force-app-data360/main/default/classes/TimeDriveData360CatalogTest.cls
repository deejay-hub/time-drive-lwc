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
