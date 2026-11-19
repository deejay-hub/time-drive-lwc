/**
 * Which day an item is on, whatever the viewer's time zone: tasks by their due
 * date, open or done (not the day they were saved as done), all-day events by their
 * date (not their midnight-GMT start), and dates an Apex source gives as text.
 * Each runs as a user in Los Angeles (UTC-8) and in Tonga (UTC+13), where a
 * date read as midnight GMT lands on the wrong day.
 */
@IsTest
private class TimeDriveDatesTest {
  private static final List<String> ZONES = new List<String>{ 'America/Los_Angeles', 'Pacific/Tongatapu' };

  private static Time_Drive_Source__mdt source(String objectName, String dateField, String type) {
    return new Time_Drive_Source__mdt(
      DeveloperName = 'Test_' + objectName,
      Label = objectName + 's',
      Active__c = true,
      Kind__c = TimeDriveContext.KIND_SALESFORCE,
      Parent_Object__c = 'Contact',
      Object_Name__c = objectName,
      Date_Field__c = dateField,
      Parent_Field__c = 'WhoId',
      Title__c = '{Subject}',
      Event_Type__c = type,
      Max_Records__c = 100
    );
  }

  private static TimeDriveContext context(Id contactId, Time_Drive_Source__mdt s) {
    return new TimeDriveContext(contactId, 'Contact', Datetime.now().addYears(-1), s, null, null);
  }

  private static Map<String, TimeDriveController.EngagementEvent> plotted(TimeDriveContext context) {
    Map<String, TimeDriveController.EngagementEvent> byTitle = new Map<String, TimeDriveController.EngagementEvent>();
    for (
      TimeDriveController.EngagementEvent e : TimeDrivePlotter.plot(
        context,
        new TimeDriveSoqlProvider().getRows(context)
      )
    ) {
      byTitle.put(e.title, e);
    }
    return byTitle;
  }

  private static Map<String, Integer> counted(TimeDriveContext context) {
    Map<String, Integer> byDay = new Map<String, Integer>();
    for (TimeDriveContext.DayCount c : new TimeDriveSoqlProvider().countDays(context, TimeDriveContext.UNIT_DAY)) {
      byDay.put(c.dayKey, (byDay.get(c.dayKey) ?? 0) + c.count);
    }
    return byDay;
  }

  @IsTest
  static void tasksAreOnTheirDueDateOpenOrDone() {
    for (String zone : ZONES) {
      System.runAs(TimeDriveTestData.adminIn(zone)) {
        Contact c = new Contact(LastName = 'Dates ' + zone);
        insert c;
        Date due = Date.today().addDays(-3);
        Date longAgo = Date.today().addDays(-10);
        // Created done today, as logged or imported history is: its due date is when it happened.
        insert new List<Task>{
          new Task(WhoId = c.Id, Subject = 'Open', ActivityDate = due, Status = 'Not Started'),
          new Task(WhoId = c.Id, Subject = 'Done', ActivityDate = longAgo, Status = 'Completed')
        };

        Map<String, TimeDriveController.EngagementEvent> byTitle = plotted(
          context(c.Id, source('Task', 'ActivityDate', 'task'))
        );
        Assert.areEqual(due, byTitle.get('Open').occurredAt.date(), zone + ': an open task is on its due date');
        Assert.isTrue(byTitle.get('Open').dateOnly, zone + ': with no time');
        Assert.areEqual(longAgo, byTitle.get('Done').occurredAt.date(), zone + ': so is a done one');
        Assert.isTrue(byTitle.get('Done').dateOnly, zone + ': also with no time');

        Map<String, Integer> byDay = counted(context(c.Id, source('Task', 'ActivityDate', 'task')));
        Assert.areEqual(1, byDay.get(String.valueOf(due)), zone + ': counted on its due date: ' + byDay);
        Assert.areEqual(1, byDay.get(String.valueOf(longAgo)), zone + ': the done one on its own: ' + byDay);
        Assert.isFalse(
          byDay.containsKey(String.valueOf(Date.today())),
          zone + ': not on the day it was saved done: ' + byDay
        );
      }
    }
  }

  @IsTest
  static void allDayEventsStayOnTheirDay() {
    for (String zone : ZONES) {
      System.runAs(TimeDriveTestData.adminIn(zone)) {
        Contact c = new Contact(LastName = 'Events ' + zone);
        insert c;
        Date day = Date.today().addDays(-2);
        Datetime meeting = Datetime.now().addHours(-5);
        insert new List<Event>{
          new Event(
            WhoId = c.Id,
            Subject = 'Offsite',
            IsAllDayEvent = true,
            ActivityDate = day,
            DurationInMinutes = 1440
          ),
          new Event(WhoId = c.Id, Subject = 'Meeting', StartDateTime = meeting, EndDateTime = meeting.addMinutes(30))
        };
        Map<String, TimeDriveController.EngagementEvent> byTitle = plotted(
          context(c.Id, source('Event', 'StartDateTime', 'event'))
        );
        Assert.areEqual(day, byTitle.get('Offsite').occurredAt.date(), zone + ': an all-day event is on its own day');
        Assert.isTrue(byTitle.get('Offsite').allDay, zone + ': and says all day');
        Assert.areEqual(
          meeting.date(),
          byTitle.get('Meeting').occurredAt.date(),
          zone + ': a timed one is when it starts'
        );

        Map<String, Integer> byDay = counted(context(c.Id, source('Event', 'StartDateTime', 'event')));
        Assert.areEqual(1, byDay.get(String.valueOf(day)), zone + ': counted on its day: ' + byDay);
        Assert.isFalse(byDay.containsKey(String.valueOf(day.addDays(-1))), zone + ': not the day before: ' + byDay);
      }
    }
  }

  @IsTest
  static void pagesThroughEveryTaskOnce() {
    System.runAs(TimeDriveTestData.adminIn('America/Los_Angeles')) {
      Contact c = new Contact(LastName = 'Pages');
      insert c;
      insert new List<Task>{
        new Task(WhoId = c.Id, Subject = 'Open', ActivityDate = Date.today().addDays(-3), Status = 'Not Started'),
        new Task(WhoId = c.Id, Subject = 'Open too', ActivityDate = Date.today().addDays(-3), Status = 'Not Started'),
        new Task(WhoId = c.Id, Subject = 'Done', ActivityDate = Date.today().addDays(-20), Status = 'Completed'),
        new Task(WhoId = c.Id, Subject = 'Done too', ActivityDate = Date.today().addDays(-30), Status = 'Completed')
      };
      Time_Drive_Source__mdt s = source('Task', 'ActivityDate', 'task');
      List<String> seen = new List<String>();
      Datetime pageAt;
      Id pageId;
      for (Integer guard = 0; guard < 10; guard++) {
        TimeDriveContext context = context(c.Id, s);
        context.pageSize = 1;
        context.pageAt = pageAt;
        context.pageId = pageId;
        List<TimeDriveController.EngagementEvent> page = TimeDrivePlotter.plot(
          context,
          new TimeDriveSoqlProvider().getRows(context)
        );
        if (page.isEmpty()) {
          break;
        }
        seen.add(page[0].title);
        pageAt = page[0].occurredAt;
        pageId = page[0].recordId;
      }
      Assert.areEqual(4, seen.size(), 'every task once, one a page: ' + seen);
      Assert.areEqual(4, new Set<String>(seen).size(), 'none twice: ' + seen);
      // Newest first, by due date: the two open three days ago, then the done ones.
      Assert.areEqual(new Set<String>{ 'Open', 'Open too' }, new Set<String>{ seen[0], seen[1] }, String.valueOf(seen));
      Assert.areEqual(
        new List<String>{ 'Done', 'Done too' },
        new List<String>{ seen[2], seen[3] },
        String.valueOf(seen)
      );
    }
  }

  @IsTest
  static void textDatesAreReadOrSaidNotHidden() {
    for (String zone : ZONES) {
      System.runAs(TimeDriveTestData.adminIn(zone)) {
        TimeDriveContext context = new TimeDriveContext(null, null, null);
        context.plotBy('When').title('{Name}');
        List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.plot(
          context,
          new List<TimeDriveRow>{
            new TimeDriveRow(new Map<String, Object>{ 'Id' => 'a', 'Name' => 'A day', 'When' => '2026-11-12' }),
            new TimeDriveRow(
              new Map<String, Object>{ 'Id' => 'b', 'Name' => 'In GMT', 'When' => '2026-11-12T09:00:00Z' }
            ),
            new TimeDriveRow(
              new Map<String, Object>{ 'Id' => 'c', 'Name' => 'Offset', 'When' => '2026-11-12T20:00:00+11:00' }
            ),
            new TimeDriveRow(new Map<String, Object>{ 'Id' => 'd', 'Name' => 'No zone', 'When' => '2026-11-12 09:30' }),
            new TimeDriveRow(new Map<String, Object>{ 'Id' => 'e', 'Name' => 'Not a date', 'When' => 'soon' })
          }
        );
        Map<String, TimeDriveController.EngagementEvent> byTitle = new Map<String, TimeDriveController.EngagementEvent>();
        for (TimeDriveController.EngagementEvent e : events) {
          byTitle.put(e.title, e);
        }
        Assert.areEqual(4, events.size(), zone + ': the unreadable one is left out');
        Assert.areEqual(
          Date.newInstance(2026, 11, 12),
          byTitle.get('A day').occurredAt.date(),
          zone + ': a day is its day'
        );
        Assert.isTrue(byTitle.get('A day').dateOnly, zone);
        Datetime nineGmt = Datetime.newInstanceGmt(2026, 11, 12, 9, 0, 0);
        Assert.areEqual(nineGmt, byTitle.get('In GMT').occurredAt, zone + ': Z is GMT');
        Assert.areEqual(nineGmt, byTitle.get('Offset').occurredAt, zone + ': an offset is that moment');
        Assert.areEqual(
          Datetime.newInstance(2026, 11, 12, 9, 30, 0),
          byTitle.get('No zone').occurredAt,
          zone + ': no zone is the user’s clock'
        );
        Assert.areEqual(1, context.warnings.size(), zone + ': and it is said: ' + context.warnings);
        Assert.areEqual(
          String.format(Label.Time_Drive_Server_Unreadable_Dates, new List<String>{ context.source.Label ?? '', '1' }),
          context.warnings[0],
          zone + ': with how many'
        );
      }
    }
  }
}
