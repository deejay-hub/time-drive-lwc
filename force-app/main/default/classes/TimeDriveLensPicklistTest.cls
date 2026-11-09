// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class TimeDriveLensPicklistTest {
  @IsTest
  static void offersAllAndTheLensesTheOrgOffersWithAllTheDefault() {
    TimeDriveLensPicklist picklist = new TimeDriveLensPicklist();
    Assert.areEqual('All', picklist.getDefaultValue().getValue());

    List<String> offered = new List<String>();
    for (Integer i = 0; i < picklist.getValues().size(); i++) {
      offered.add((String) picklist.getValues().get(i).getValue());
    }
    Assert.isTrue(offered.contains('All'), 'All is always an option');
    for (Time_Drive_View__mdt v : TimeDriveConfig.activeViews()) {
      Assert.isTrue(offered.contains(v.DeveloperName), v.DeveloperName);
    }
  }
}
