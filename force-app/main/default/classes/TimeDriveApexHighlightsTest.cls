/**
 * An Apex source's highlight: the key (or field path) it names marks the rows
 * where the value is true, says the key's (or field's) name, and is read with
 * the source's query; a name that isn't a key, or a field its query didn't
 * read, marks nothing. Also: an Apex source's own tests can read its counts.
 */
@IsTest
private class TimeDriveApexHighlightsTest {
  private static TimeDriveContext apexContext(Id recordId) {
    return new TimeDriveContext(recordId, Datetime.now().addDays(-30), Datetime.now().addDays(1));
  }

  private static Time_Drive_Highlight__mdt highlight(String key) {
    return new Time_Drive_Highlight__mdt(Field__c = key, Icon__c = 'utility:flag', Colour__c = '#DD7A01');
  }

  @IsTest
  static void aKeyThatIsTrueMarksTheRow() {
    TimeDriveContext context = apexContext(UserInfo.getUserId());
    context.draftHighlights = new List<Time_Drive_Highlight__mdt>{ highlight('Hot') };
    context.plotBy('Day').title('{Summary}');
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.plot(
      context,
      new List<TimeDriveRow>{
        new TimeDriveRow(
          new Map<String, Object>{ 'Id' => 'a', 'Day' => Date.today(), 'Summary' => 'Big deal', 'Hot' => true }
        ),
        new TimeDriveRow(
          new Map<String, Object>{ 'Id' => 'b', 'Day' => Date.today(), 'Summary' => 'Small deal', 'Hot' => false }
        ),
        new TimeDriveRow(new Map<String, Object>{ 'Id' => 'c', 'Day' => Date.today(), 'Summary' => 'No say' })
      }
    );
    Map<String, TimeDriveController.EngagementEvent> byTitle = new Map<String, TimeDriveController.EngagementEvent>();
    for (TimeDriveController.EngagementEvent e : events) {
      byTitle.put(e.title, e);
    }
    Assert.areEqual(1, byTitle.get('Big deal').flags?.size(), 'true: marked');
    Assert.areEqual('utility:flag', byTitle.get('Big deal').flags[0].icon);
    Assert.areEqual('Hot', byTitle.get('Big deal').flags[0].text, 'a map key says its own name');
    Assert.isNull(byTitle.get('Small deal').flags, 'false: not marked');
    Assert.isNull(byTitle.get('No say').flags, 'missing: not marked');
  }

  @IsTest
  static void aRecordRowsCheckboxIsReadWithTheSourcesQuery() {
    Contact c = new Contact(LastName = 'Apex highlight');
    insert c;
    insert new Task(
      WhoId = c.Id,
      Subject = 'Urgent',
      Priority = 'High',
      ActivityDate = Date.today(),
      Status = 'Not Started'
    );
    TimeDriveContext context = apexContext(c.Id);
    context.draftHighlights = new List<Time_Drive_Highlight__mdt>{ highlight('IsHighPriority') };
    context.plotBy('ActivityDate').title('{Subject}');
    // fieldsToQuery asks for the highlight's field, as for the details.
    List<String> fields = context.fieldsToQuery(new List<String>{ 'Id', 'ActivityDate' });
    Assert.isTrue(fields.contains('IsHighPriority'), String.valueOf(fields));
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    for (
      SObject t : Database.query('SELECT ' + String.join(fields, ', ') + ' FROM Task WHERE WhoId = \'' + c.Id + '\'')
    ) {
      rows.add(new TimeDriveRow(t));
    }
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.plot(context, rows);
    Assert.areEqual(1, events[0].flags?.size());
    Assert.areEqual(Task.IsHighPriority.getDescribe().getLabel(), events[0].flags[0].text, 'a field says its label');

    // A query that didn't read it: no mark, and no failure.
    List<TimeDriveRow> bare = new List<TimeDriveRow>();
    for (Task t : [SELECT Id, Subject, ActivityDate FROM Task WHERE WhoId = :c.Id]) {
      bare.add(new TimeDriveRow(t));
    }
    Assert.isNull(TimeDrivePlotter.plot(context, bare)[0].flags);
  }

  @IsTest
  static void aNameThatIsntAKeyIsLeftOut() {
    TimeDriveContext context = apexContext(UserInfo.getUserId());
    context.draftHighlights = new List<Time_Drive_Highlight__mdt>{ highlight('Id FROM User WHERE') };
    context.plotBy('Day').title('{Summary}');
    Assert.isTrue(context.highlightRules().isEmpty());
    Assert.areEqual(
      new List<String>{ 'Id', 'Summary' },
      context.fieldsToQuery(new List<String>{ 'Id' }),
      'the title\'s field, but not the highlight\'s'
    );
  }

  @IsTest
  static void anApexSourcesTestsCanReadItsCounts() {
    TimeDriveContext context = apexContext(UserInfo.getUserId());
    List<TimeDriveContext.DayCount> counts = context.counter(TimeDriveContext.UNIT_DAY).add(Date.today(), 3).counts();
    Assert.areEqual(1, counts.size());
    Assert.areEqual(String.valueOf(Date.today()), counts[0].dayKey);
    Assert.areEqual(3, counts[0].count);
  }
}
