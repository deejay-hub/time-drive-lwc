/**
 * Long text on the timeline: a title or subtitle shows at most 150
 * characters and a detail at most 500, cut with an ellipsis (at a word's end
 * when one is near), so a task's 32,000-character Description doesn't fill
 * the response. Short text is left as it is.
 */
@IsTest
private class TimeDriveLongTextTest {
  @IsTest
  static void textIsCutWithAnEllipsisOnlyWhenTooLong() {
    Assert.isNull(TimeDrivePlotter.shorten(null, 10));
    Assert.areEqual('Short', TimeDrivePlotter.shorten('Short', 10), 'short text stays');
    Assert.areEqual('0123456789', TimeDrivePlotter.shorten('0123456789', 10), 'exactly the limit stays');
    String cut = TimeDrivePlotter.shorten('aaaaaaaaaaaaaaaaaaaa', 10);
    Assert.areEqual(10, cut.length());
    Assert.isTrue(cut.endsWith('…'), cut);
    // Near the end there's a space: cut at the word, not through it.
    Assert.areEqual('Send the…', TimeDrivePlotter.shorten('Send the proposal', 10));
  }

  @IsTest
  static void aLongDescriptionIsShortenedOnTheTimeline() {
    System.runAs(TimeDriveTestData.adminIn('America/Los_Angeles')) {
      Contact c = new Contact(LastName = 'Long notes');
      insert c;
      String notes = 'Notes from the call. '.repeat(400);
      insert new Task(
        WhoId = c.Id,
        Subject = 'Call',
        Description = notes,
        ActivityDate = Date.today(),
        Status = 'Not Started'
      );
      Time_Drive_Source__mdt s = new Time_Drive_Source__mdt(
        DeveloperName = 'Tasks',
        Label = 'Tasks',
        Active__c = true,
        Kind__c = TimeDriveContext.KIND_SALESFORCE,
        Parent_Object__c = 'Contact',
        Object_Name__c = 'Task',
        Date_Field__c = 'ActivityDate',
        Parent_Field__c = 'WhoId',
        Event_Type__c = 'task',
        Title__c = '{Description}',
        Subtitle__c = '{Description}',
        Max_Records__c = 100
      );
      TimeDriveContext context = new TimeDriveContext(c.Id, 'Contact', Datetime.now().addDays(-30), s, null, null);
      context.draftDetailFields = new List<Time_Drive_Detail_Field__mdt>{
        new Time_Drive_Detail_Field__mdt(Label = 'Notes', Field__c = 'Description')
      };
      TimeDriveController.EngagementEvent e = TimeDrivePlotter.run(new TimeDriveSoqlProvider(), context)[0];
      Assert.isTrue(e.title.length() <= TimeDrivePlotter.MAX_LINE, String.valueOf(e.title.length()));
      Assert.isTrue(e.title.endsWith('…'));
      Assert.isTrue(e.subtitle.length() <= TimeDrivePlotter.MAX_LINE, String.valueOf(e.subtitle.length()));
      Assert.isTrue(
        e.details[0].value.length() <= TimeDrivePlotter.MAX_DETAIL,
        String.valueOf(e.details[0].value.length())
      );
      Assert.isTrue(e.details[0].value.startsWith('Notes from the call.'), 'it keeps the start');
      Assert.isTrue(e.details[0].value.endsWith('…'));
    }
  }
}
