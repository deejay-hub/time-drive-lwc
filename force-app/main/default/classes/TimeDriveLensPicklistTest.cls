// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class TimeDriveLensPicklistTest {
  @IsTest
  static void offersAllAndTheLensesTheOrgOffersWithAllTheDefault() {
    TimeDriveConfig.testViews = new List<Time_Drive_View__mdt>{
      new Time_Drive_View__mdt(
        DeveloperName = 'All',
        Label = 'All',
        Menu_Label__c = '$Label.Time_Drive_View_All',
        Sequence__c = 99
      ),
      new Time_Drive_View__mdt(DeveloperName = 'Sales', Label = 'Sales', Sequence__c = 10),
      new Time_Drive_View__mdt(
        DeveloperName = 'Service',
        Label = 'Service',
        Menu_Label__c = '$Label.Time_Drive_View_Service',
        Sequence__c = 20
      ),
      new Time_Drive_View__mdt(DeveloperName = 'Digital', Label = 'Digital', Sequence__c = 30)
    };
    // Switched off in Setup (saved as an admin, as Setup does): not offered.
    System.runAs(TimeDriveTestData.setupAdmin()) {
      insert new Time_Drive_Setup__c(Name = 'Org', Hidden_Views__c = 'Digital');
    }

    TimeDriveLensPicklist picklist = new TimeDriveLensPicklist();
    Assert.areEqual('All', picklist.getDefaultValue().getValue());
    Assert.areEqual(Label.Time_Drive_View_All, picklist.getDefaultValue().getLabel());

    Map<String, String> offered = new Map<String, String>();
    for (Integer i = 0; i < picklist.getValues().size(); i++) {
      VisualEditor.DataRow row = picklist.getValues().get(i);
      offered.put((String) row.getValue(), row.getLabel());
    }
    // All first, then by sequence; the hidden one left out.
    Assert.areEqual(new Set<String>{ 'All', 'Sales', 'Service' }, offered.keySet());
    Assert.areEqual('All', (String) picklist.getValues().get(0).getValue());
    Assert.areEqual(Label.Time_Drive_View_All, offered.get('All'));
    Assert.areEqual('Sales', offered.get('Sales'), 'no label of its own: the view\'s');
    Assert.areEqual(Label.Time_Drive_View_Service, offered.get('Service'), 'its custom label, translated');
  }
}
