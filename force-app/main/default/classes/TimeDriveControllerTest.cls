// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
// Size, parameter lists and field counts follow the platform's entry points, its cases and the data the components exchange;
// splitting them up would only scatter what belongs together.
@SuppressWarnings(
  'PMD.ApexUnitTestClassShouldHaveRunAs, PMD.CyclomaticComplexity, PMD.CognitiveComplexity, PMD.ExcessiveParameterList, PMD.NcssCount'
)
@IsTest
private class TimeDriveControllerTest {
  // A well-formed Id for tests: the object's key prefix and a number.
  private static Id fakeId(String prefix, Integer n) {
    return Id.valueOf(prefix + String.valueOf(n).leftPad(12, '0'));
  }

  // The sources the timeline once shipped with, in place of the org's.
  static {
    TimeDriveTestData.useShipped();
  }

  @TestSetup
  static void makeData() {
    // Standard objects only: orders and a review are Tasks ("Order …"
    // tasks; Completed is delivered, Deferred canceled).
    Account store = new Account(Name = 'The Savory Spot');
    insert store;
    Contact customer = new Contact(FirstName = 'Ada', LastName = 'Shift', AccountId = store.Id);
    insert customer;

    Date placed = Date.today().addDays(-3);
    insert new List<Task>{
      new Task(
        WhoId = customer.Id,
        Subject = 'Order 1001',
        Status = 'Completed',
        ActivityDate = placed,
        Description = 'Pad thai and spring rolls'
      ),
      new Task(
        WhoId = customer.Id,
        Subject = 'Order 1002',
        Status = 'Deferred',
        ActivityDate = placed.addDays(-10),
        Description = 'Store closed'
      ),
      new Task(
        WhoId = customer.Id,
        Subject = 'Review: 4 out of 5',
        Status = 'Completed',
        Description = 'Great pad thai'
      )
    };
    insert new Case(ContactId = customer.Id, Subject = 'Missing item', Status = 'New', Origin = 'Web');
    Account company = new Account(Name = 'Ada Catering Co');
    insert company;
    Opportunity open = new Opportunity(
      Name = 'Office lunches 2027',
      AccountId = company.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30),
      Amount = 12000
    );
    Opportunity won = new Opportunity(
      Name = 'Holiday party',
      AccountId = company.Id,
      StageName = 'Closed Won',
      CloseDate = Date.today().addDays(-5),
      Amount = 3500
    );
    insert new List<Opportunity>{ open, won };
    insert new OpportunityContactRole(OpportunityId = open.Id, ContactId = customer.Id, Role = 'Decision Maker');
    insert new OpportunityContactRole(OpportunityId = won.Id, ContactId = customer.Id, Role = 'Business User');
  }

  private static Id contactId() {
    return [SELECT Id FROM Contact LIMIT 1].Id;
  }

  private static Integer countOf(TimeDriveController.TimelineResult result, String type) {
    Integer n = 0;
    for (TimeDriveController.EngagementEvent e : result.events) {
      if (e.type == type) {
        n++;
      }
    }
    return n;
  }

  @IsTest
  static void everySourcesEventsMergeNewestFirst() {
    Test.startTest();
    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(contactId());
    Test.stopTest();

    Assert.areEqual(2, countOf(result, 'purchase'), 'both real orders');
    Assert.areEqual(1, countOf(result, 'delivered'));
    Assert.areEqual(1, countOf(result, 'canceled'));
    Assert.areEqual(1, countOf(result, 'review'));
    Assert.areEqual(1, countOf(result, 'case'));

    // Newest first.
    for (Integer i = 1; i < result.events.size(); i++) {
      Assert.isTrue(result.events[i - 1].occurredAt >= result.events[i].occurredAt, 'sorted newest first');
    }
  }

  @IsTest
  static void opportunitiesTheContactIsOnArePlotted() {
    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(contactId());
    Assert.areEqual(2, countOf(result, 'opportunity'), 'both opportunities opened in the window');
    Assert.areEqual(1, countOf(result, 'opportunity_won'));
    Assert.areEqual(0, countOf(result, 'opportunity_lost'));
    for (TimeDriveController.EngagementEvent e : result.events) {
      if (e.type == 'opportunity_won') {
        Assert.areEqual('Sales', e.category);
        Assert.isTrue(e.subtitle.contains('Holiday party'));
        Assert.isNotNull(e.recordId, 'CRM events link to their record');
        Assert.areEqual(Opportunity.SObjectType, e.recordId.getSObjectType());
      }
    }
  }

  @IsTest
  static void summaryCountsEveryDayAndPagesReturnThoseDays() {
    Id customer = contactId();
    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, null, null);
    Integer counted = 0;
    Integer orders = 0;
    for (TimeDriveController.DaySummary day : summary.days) {
      counted += day.count;
      orders += day.orders;
    }
    Assert.areEqual(summary.total, counted, 'every event is in a day');
    Assert.areEqual(summary.unfilteredTotal, summary.total, 'no filters');
    Assert.areEqual(2, orders, 'both orders');
    Assert.isFalse(summary.types.isEmpty());
    Assert.isFalse(summary.noSources, 'the Contact page has sources');
    Assert.areEqual(Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel(), summary.page);
    // Every source in the view is offered to the filters, items or not.
    Set<String> offered = new Set<String>();
    for (TimeDriveController.TypeCount t : summary.types) {
      offered.add(t.type);
    }
    for (Time_Drive_Source__mdt s : TimeDriveConfig.allSources().values()) {
      if (s.Active__c == true && String.isNotBlank(s.Event_Type__c) && s.Parent_Object__c == 'Contact') {
        Assert.isTrue(offered.contains(s.Event_Type__c), s.Event_Type__c + ' is offered');
      }
    }
  }

  @IsTest
  static void allIsALensASourceIsInOrNot() {
    // Open and closed cases each in a lens of their own, all cases in All, and one in no lens (All).
    Id customer = contactId();
    Time_Drive_Source__mdt everyCase = source('All_Cases', 'Case', 'CreatedDate', 'ContactId');
    everyCase.Lenses__c = 'All';
    Time_Drive_Source__mdt open = source('Open_Cases', 'Case', 'CreatedDate', 'ContactId');
    open.Lenses__c = 'Service';
    Time_Drive_Source__mdt untagged = source('Untagged_Cases', 'Case', 'CreatedDate', 'ContactId');
    untagged.Category__c = null;
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ everyCase, open, untagged };

    Integer one = TimeDriveController.getSummary(customer, null, null, null, null).total / 3;
    Assert.isTrue(one > 0, 'the setup has cases to show');
    Assert.areEqual(
      2 * one,
      TimeDriveController.getSummary(customer, new List<String>{ 'All' }, null, null, null).total,
      'All: the source in All and the one in no lens, not the one only in Service'
    );
    Assert.areEqual(
      one,
      TimeDriveController.getSummary(customer, new List<String>{ 'Service' }, null, null, null).total,
      'Service: only the source in it'
    );
  }

  @IsTest
  static void countedSourcesArentCappedByMaxRecords() {
    Id customer = contactId();
    insert new Case(ContactId = customer, Subject = 'Wrong item', Status = 'New', Origin = 'Web');
    Time_Drive_Source__mdt cases = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    cases.Max_Records__c = 1;
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ cases };

    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, null, null);
    Assert.areEqual(2, summary.total, 'counted, not read');
    Assert.isTrue(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
  }

  @IsTest
  static void busyDaysOfCountedSourcesComeFromTheirCounts() {
    Id customer = contactId();
    List<Case> busy = new List<Case>();
    for (Integer i = 0; i < 60; i++) {
      busy.add(new Case(ContactId = customer, Subject = 'Busy ' + i, Status = 'New', Origin = 'Web'));
    }
    insert busy;
    Case older = new Case(ContactId = customer, Subject = 'Older', Status = 'New', Origin = 'Web');
    insert older;
    Datetime threeDaysAgo = Datetime.now().addDays(-3);
    Test.setCreatedDate(older.Id, threeDaysAgo);
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };

    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, null, null);
    String today = Datetime.now().format('yyyy-MM-dd');
    String quiet = threeDaysAgo.format('yyyy-MM-dd');
    Assert.areEqual(2, summary.days.size());
    Assert.areEqual(today, summary.days[0].key);
    Assert.areEqual(61, summary.days[0].count, 'the 60 and the setup case');

    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today, quiet },
      null
    );
    Assert.areEqual(2, page.size(), 'the busy day grouped, the quiet day in full');
    TimeDriveController.EngagementEvent grouped = page[0];
    Assert.isTrue(grouped.grouped);
    Assert.areEqual(61, grouped.groupCount);
    Assert.areEqual(today, grouped.dayKey);
    Assert.isTrue(grouped.firstAt <= grouped.occurredAt);
    Assert.areEqual('Salesforce · Case', grouped.sourceLabel);
    Assert.isFalse(page[1].grouped);
    Assert.areEqual(older.Id, page[1].recordId);
    Assert.areEqual(quiet, page[1].dayKey);
  }

  @IsTest
  static void pagesCountOnlyThePeriodsTheSummaryFoundBusy() {
    Id customer = contactId();
    List<Case> busy = new List<Case>();
    for (Integer i = 0; i < 60; i++) {
      busy.add(new Case(ContactId = customer, Subject = 'Busy ' + i, Status = 'New', Origin = 'Web'));
    }
    insert busy;
    Case older = new Case(ContactId = customer, Subject = 'Older', Status = 'New', Origin = 'Web');
    insert older;
    Datetime threeDaysAgo = Datetime.now().addDays(-3);
    Test.setCreatedDate(older.Id, threeDaysAgo);
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    String today = Datetime.now().format('yyyy-MM-dd');
    String quiet = threeDaysAgo.format('yyyy-MM-dd');

    // A quiet page: no count at all, just the rows (one query). The Time Drive
    // records are read once and kept for the request (and across requests in
    // Platform Cache), so they are read before this is measured.
    TimeDriveConfig.sources('Contact');
    Integer before = Limits.getQueries();
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ quiet },
      new List<String>()
    );
    Assert.areEqual(1, page.size());
    Assert.areEqual(older.Id, page[0].recordId);
    // The rows (one query); what the user may do with them is asked for when
    // a row's menu opens, not here.
    Assert.areEqual(1, Limits.getQueries() - before, 'the rows only: no count, no rights');

    // A busy day and a quiet one: the busy one counted and grouped, the
    // quiet one read, the same as counting both.
    page = TimeDriveController.getDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today, quiet },
      new List<String>{ today }
    );
    Assert.areEqual(2, page.size());
    Assert.isTrue(page[0].grouped);
    Assert.areEqual(61, page[0].groupCount);
    Assert.areEqual(older.Id, page[1].recordId);

    // A summary out of date (it called today quiet): read as rows, and
    // grouped by type as any busy day read as rows is.
    page = TimeDriveController.getDays(customer, null, null, null, null, new List<String>{ today }, new List<String>());
    Assert.areEqual(1, page.size());
    Assert.isTrue(page[0].grouped);
    Assert.areEqual(61, page[0].groupCount);
  }

  @IsTest
  static void theSummarysSourceCountsSaveTheDaysQueries() {
    Id customer = contactId();
    List<Case> busy = new List<Case>();
    for (Integer i = 0; i < 60; i++) {
      busy.add(new Case(ContactId = customer, Subject = 'Busy ' + i, Status = 'New', Origin = 'Web'));
    }
    insert busy;
    Case older = new Case(ContactId = customer, Subject = 'Older', Status = 'New', Origin = 'Web');
    insert older;
    Datetime threeDaysAgo = Datetime.now().addDays(-3);
    Test.setCreatedDate(older.Id, threeDaysAgo);
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    String today = Datetime.now().format('yyyy-MM-dd');
    String quiet = threeDaysAgo.format('yyyy-MM-dd');

    // The summary says which sources it counted, and what each period holds
    // of them (the counts only for a busy period).
    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, null, null);
    Assert.areEqual(new List<String>{ 'Cases' }, summary.counted);
    for (TimeDriveController.DaySummary d : summary.days) {
      Assert.areEqual(new List<Integer>{ 0 }, d.src);
      if (d.key == today) {
        Assert.areEqual(new List<Integer>{ 61 }, d.n);
      } else {
        Assert.isNull(d.n, 'a quiet period keeps no counts');
      }
    }

    // A busy period's grouped row from the summary's count: no count query,
    // and it stands for the whole day.
    TimeDriveController.BusyCount known = new TimeDriveController.BusyCount();
    known.key = today;
    known.source = 'Cases';
    known.count = 61;
    Integer before = Limits.getQueries();
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getPageDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today },
      new List<String>{ today },
      new List<String>(),
      new List<TimeDriveController.BusyCount>{ known },
      null
    );
    Assert.areEqual(1, page.size());
    Assert.isTrue(page[0].grouped);
    Assert.isTrue(page[0].allDay, 'a count for the day says no hour');
    Assert.areEqual(61, page[0].groupCount);
    Integer withHint = Limits.getQueries() - before;
    before = Limits.getQueries();
    TimeDriveController.getDays(customer, null, null, null, null, new List<String>{ today }, new List<String>{ today });
    Assert.isTrue(withHint < Limits.getQueries() - before, 'the hint saves the count');

    // A source the summary found nothing in is not asked.
    before = Limits.getQueries();
    page = TimeDriveController.getPageDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ quiet },
      new List<String>(),
      new List<String>{ 'Cases' },
      null,
      null
    );
    Assert.isTrue(page.isEmpty());
    Assert.areEqual(0, Limits.getQueries() - before, 'no query for a source known to be empty');
  }

  @IsTest
  static void onlyFieldsThatCanBeEmptyAreCheckedForADate() {
    Id customer = contactId();
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Tasks', 'Task', 'ActivityDate', 'WhoId'),
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    TimeDriveDiagnostics.begin();
    TimeDriveController.getTimeline(customer, null, null, null, null, null, null, null, null);
    TimeDriveDiagnostics.finish();
    Boolean sawTask = false;
    for (TimeDriveDiagnostics.Query q : TimeDriveDiagnostics.queries) {
      if (q.soql.contains('FROM Task ')) {
        sawTask = true;
        Assert.isTrue(q.soql.contains('ActivityDate != null'), 'a nillable date must have a value: ' + q.soql);
      } else if (q.soql.contains('FROM Case ')) {
        Assert.isFalse(q.soql.contains('CreatedDate != null'), 'a date that is always set needs no check');
      }
    }
    Assert.isTrue(sawTask, 'the Tasks were queried');
  }

  @IsTest
  static void daysThatFollowOneAnotherInTheSummaryAreReadAsOneRange() {
    Id customer = contactId();
    // Items on five days with gaps between them, and one more further back.
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 6; i++) {
      cases.add(new Case(ContactId = customer, Subject = 'Case ' + i, Status = 'New', Origin = 'Web'));
    }
    insert cases;
    List<String> keys = new List<String>();
    Integer[] daysBack = new List<Integer>{ 1, 3, 4, 8, 9, 20 };
    for (Integer i = 0; i < cases.size(); i++) {
      Datetime at = Datetime.now().addDays(-daysBack[i]);
      Test.setCreatedDate(cases[i].Id, at);
      keys.add(at.format('yyyy-MM-dd'));
    }
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    // The first five follow one another in the summary: one run. The sixth
    // is not asked with them.
    List<String> run = new List<String>{ keys[4], keys[3], keys[2], keys[1], keys[0] };
    String together = String.join(run, ',');

    TimeDriveDiagnostics.begin();
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getPageDays(
      customer,
      null,
      null,
      null,
      null,
      run,
      new List<String>(),
      null,
      null,
      new List<String>{ together }
    );
    TimeDriveDiagnostics.finish();
    Assert.areEqual(5, page.size());
    Integer rangesAsRun = TimeDriveDiagnostics.queries[0].soql.split('CreatedDate >= ').size() - 1;
    Assert.areEqual(1, rangesAsRun, 'one range for the run');

    // Without the runs: a range for each day, the same rows.
    TimeDriveDiagnostics.begin();
    List<TimeDriveController.EngagementEvent> apart = TimeDriveController.getPageDays(
      customer,
      null,
      null,
      null,
      null,
      run,
      new List<String>(),
      null,
      null,
      null
    );
    TimeDriveDiagnostics.finish();
    Assert.areEqual(5, apart.size());
    Assert.areEqual(5, TimeDriveDiagnostics.queries[0].soql.split('CreatedDate >= ').size() - 1, 'a range for each');
    Set<Id> ids = new Set<Id>();
    for (TimeDriveController.EngagementEvent e : page) {
      ids.add(e.recordId);
    }
    for (TimeDriveController.EngagementEvent e : apart) {
      Assert.isTrue(ids.contains(e.recordId), 'the same rows either way');
    }
  }

  @IsTest
  static void quietDaysAreReadInFullWhateverMaxRecords() {
    // Max Records 5, and 12 items over three quiet days: each read that
    // comes back full is read again from its oldest day, so none are missed.
    Contact fresh = new Contact(LastName = 'Read in full');
    insert fresh;
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 12; i++) {
      cases.add(new Case(ContactId = fresh.Id, Subject = 'Case ' + i, Status = 'New', Origin = 'Web'));
    }
    insert cases;
    List<String> keys = new List<String>();
    for (Integer d = 1; d <= 3; d++) {
      Datetime at = Datetime.now().addDays(-d);
      keys.add(at.format('yyyy-MM-dd'));
      for (Integer i = (d - 1) * 4; i < d * 4; i++) {
        Test.setCreatedDate(cases[i].Id, at.addMinutes(-i));
      }
    }
    Time_Drive_Source__mdt source = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    source.Max_Records__c = 5;
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source };

    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      fresh.Id,
      null,
      null,
      null,
      null,
      keys,
      new List<String>()
    );
    Assert.areEqual(12, page.size(), 'every item, though each read stops at 5');
    for (TimeDriveController.EngagementEvent e : page) {
      Assert.isFalse(e.grouped);
    }

    // One "quiet" day (the summary out of date) with more than Max Records:
    // counted, one grouped row with its true total, not 5 of its 8.
    List<Case> more = new List<Case>();
    for (Integer i = 0; i < 4; i++) {
      more.add(new Case(ContactId = fresh.Id, Subject = 'More ' + i, Status = 'New', Origin = 'Web'));
    }
    insert more;
    Datetime first = Datetime.now().addDays(-1);
    for (Case c : more) {
      Test.setCreatedDate(c.Id, first);
    }
    page = TimeDriveController.getDays(
      fresh.Id,
      null,
      null,
      null,
      null,
      new List<String>{ keys[0] },
      new List<String>()
    );
    Assert.areEqual(1, page.size(), String.valueOf(page));
    Assert.isTrue(page[0].grouped);
    Assert.areEqual(8, page[0].groupCount);
  }

  @IsTest
  static void data360ReadsStayUnderTheDmoRowLimit() {
    // Data 360 refuses a DMO query of more than 2,000 rows; a source's Max
    // Records can't take a read past it.
    Assert.areEqual(2000, TimeDriveData360Provider.MAX_DMO_ROWS);
  }

  @IsTest
  static void identityLinksAreKeptBetweenRequests() {
    TimeDriveCache.testStore = new Map<String, Object>();
    Id customer = contactId();
    String key = TimeDriveCache.key(new List<String>{ 'ids', customer, null });
    TimeDriveCache.put(key, new Set<String>{ 'UNIFIED-1', 'WEB-9' });
    List<String> warnings = new List<String>();
    TimeDriveContext context = new TimeDriveContext(customer, 'Contact', Datetime.now(), null, null, warnings);
    // Kept from an earlier request: no link object needed, no warning.
    Set<String> ids = TimeDriveData360Provider.individualIdsFor(
      customer,
      new Map<String, Schema.SObjectType>(),
      context
    );
    Assert.isTrue(
      ids.containsAll(new Set<String>{ String.valueOf(customer), 'UNIFIED-1', 'WEB-9' }),
      String.valueOf(ids)
    );
    Assert.isTrue(warnings.isEmpty(), String.join(warnings, ' | '));
    // Keys are letters and digits, within the cache's 50 characters.
    Assert.isTrue(Pattern.matches('[A-Za-z0-9]{1,50}', key), key);
    // Without a partition (as here, outside tests' stand-in), nothing breaks.
    TimeDriveCache.testStore = null;
    TimeDriveCache.put('x', 'y');
    Assert.isNull(TimeDriveCache.get('nothingKept'));
  }

  @IsTest
  static void countsAreBatchedUnderTheGroupLimit() {
    Datetime since = Datetime.newInstance(Date.newInstance(2026, 1, 1), Time.newInstance(9, 0, 0, 0));
    Datetime until = Datetime.newInstance(Date.newInstance(2026, 1, 10), Time.newInstance(17, 0, 0, 0));
    List<List<TimeDriveController.TimeWindow>> batches = TimeDriveSoqlProvider.batches(
      new List<TimeDriveController.TimeWindow>{ new TimeDriveController.TimeWindow(since, until) },
      4
    );
    Assert.areEqual(3, batches.size(), '4 days, 4 days, 2 days');
    Assert.areEqual(since, batches[0][0].since);
    Assert.areEqual(Date.newInstance(2026, 1, 4), batches[0][0].until.date());
    Assert.areEqual(Date.newInstance(2026, 1, 5), batches[1][0].since.date());
    Assert.areEqual(until, batches[2][0].until);
  }

  @IsTest
  static void periodsAreDaysWeeksFromTheFirstOfJanuaryOrMonths() {
    Assert.areEqual('2026-01-08', TimeDriveContext.periodKey(Date.newInstance(2026, 1, 9), 'week'));
    Assert.areEqual('2026-12-31', TimeDriveContext.periodKey(Date.newInstance(2026, 12, 31), 'week'));
    Assert.areEqual(Date.newInstance(2026, 12, 30), TimeDriveContext.periodEnd(Date.newInstance(2026, 12, 24), 'week'));
    Assert.areEqual(Date.newInstance(2026, 12, 31), TimeDriveContext.periodEnd(Date.newInstance(2026, 12, 31), 'week'));
    Assert.areEqual('2026-02-01', TimeDriveContext.periodKey(Date.newInstance(2026, 2, 17), 'month'));
    Assert.areEqual(Date.newInstance(2026, 2, 28), TimeDriveContext.periodEnd(Date.newInstance(2026, 2, 1), 'month'));
    Assert.areEqual('2026-02-17', TimeDriveContext.periodKey(Date.newInstance(2026, 2, 17), 'day'));
  }

  @IsTest
  static void longWindowsWithManySourcesCountByWeek() {
    Id customer = contactId();
    List<Time_Drive_Source__mdt> many = new List<Time_Drive_Source__mdt>();
    for (Integer i = 0; i < 5; i++) {
      many.add(source('Cases_' + i, 'Case', 'CreatedDate', 'ContactId'));
    }
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ many[0] };
    // Ten years back and ahead: one source still fits by day...
    Assert.areEqual('day', TimeDriveController.getSummary(customer, null, null, '10', '10').unit);

    // ...five don't (5 x 7,305 days > COUNT_ROWS), so they count by week.
    TimeDriveConfig.testSources = many;
    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, '10', '10');
    String week = TimeDriveContext.periodKey(Date.today(), 'week');
    Assert.areEqual('week', summary.unit);
    Assert.areEqual(1, summary.days.size());
    Assert.areEqual(week, summary.days[0].key, 'keyed by the week\'s first day');
    Assert.areEqual(5, summary.days[0].count, 'the case, once per source');

    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      customer,
      null,
      null,
      '10',
      '10',
      new List<String>{ week },
      null
    );
    Assert.areEqual(5, page.size());
    for (TimeDriveController.EngagementEvent e : page) {
      Assert.areEqual(week, e.dayKey, 'events come back under their week');
      Assert.isFalse(e.grouped);
    }
  }

  @IsTest
  static void quietDaysAreReadOnTheirOwnNotWithEverythingBetween() {
    // Two quiet days far apart with plenty between them, and Max Records 5:
    // read as one span, the 5 newest (all from between) would crowd out the
    // older day; read as their own spans, both come back in full.
    Id customer = contactId();
    Date older = Date.today().addDays(-100);
    Date between = Date.today().addDays(-50);
    Date newer = Date.today().addDays(-10);
    List<Task> tasks = new List<Task>{
      new Task(WhoId = customer, Subject = 'Older', ActivityDate = older, Status = 'Completed'),
      new Task(WhoId = customer, Subject = 'Newer', ActivityDate = newer, Status = 'Completed')
    };
    for (Integer i = 0; i < 20; i++) {
      tasks.add(new Task(WhoId = customer, Subject = 'Between ' + i, ActivityDate = between, Status = 'Completed'));
    }
    insert tasks;
    Time_Drive_Source__mdt source = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    source.Max_Records__c = 5;
    source.Title__c = '{Subject}';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source };

    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      customer,
      null,
      null,
      '1',
      null,
      new List<String>{ String.valueOf(older), String.valueOf(newer) },
      null
    );
    Set<String> titles = new Set<String>();
    for (TimeDriveController.EngagementEvent e : page) {
      titles.add(e.title);
    }
    Assert.areEqual(new Set<String>{ 'Older', 'Newer' }, titles);
    Assert.isTrue(Limits.getQueryRows() < 20, 'the days between aren\'t read: ' + Limits.getQueryRows());
  }

  @IsTest
  static void tasksAreReadWithAllRowsButNotDeletedOnes() {
    // ALL ROWS brings back archived Tasks and Events (a test can't archive
    // one); deleted ones, in the Recycle Bin, must still stay out.
    Contact fresh = new Contact(LastName = 'All Rows');
    insert fresh;
    Id customer = fresh.Id;
    Date day = Date.today().addDays(-3);
    Task kept = new Task(WhoId = customer, Subject = 'Kept', ActivityDate = day, Status = 'Completed');
    Task gone = new Task(WhoId = customer, Subject = 'Gone', ActivityDate = day, Status = 'Completed');
    insert new List<Task>{ kept, gone };
    delete gone;
    Time_Drive_Source__mdt source = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    source.Title__c = '{Subject}';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source };

    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, '1', null);
    Assert.areEqual(1, summary.total, 'counted without the deleted one');
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      customer,
      null,
      null,
      '1',
      null,
      new List<String>{ String.valueOf(day) },
      null
    );
    Assert.areEqual(1, page.size());
    Assert.areEqual('Kept', page[0].title);
    Assert.isTrue(TimeDriveSoqlProvider.ARCHIVED_OBJECTS.contains('Task'));
  }

  @IsTest
  static void aSourceTheFiltersHideIsNotCounted() {
    Id customer = contactId();
    insert new Task(WhoId = customer, Subject = 'A', ActivityDate = Date.today(), Status = 'Completed');
    Time_Drive_Source__mdt tasks = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    tasks.Event_Type__c = 'task';
    Time_Drive_Source__mdt cases = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ tasks, cases };

    Integer before = Limits.getQueries();
    TimeDriveController.TimelineSummary shown = TimeDriveController.getSummary(customer, null, null, '1', 'None');
    Integer allQueries = Limits.getQueries() - before;
    Assert.isTrue(shown.total > 0, 'the Tasks are counted');

    before = Limits.getQueries();
    TimeDriveController.TimelineSummary hidden = TimeDriveController.getSummary(
      customer,
      null,
      new List<String>{ 'task' },
      '1',
      'None'
    );
    Integer hiddenQueries = Limits.getQueries() - before;
    Assert.isTrue(
      hiddenQueries < allQueries,
      'the hidden Tasks source was not counted: ' + hiddenQueries + ' v ' + allQueries
    );
    Assert.isTrue(hidden.total < shown.total, 'without the Tasks: ' + hidden.total + ' v ' + shown.total);
    Assert.areEqual(hidden.total, hidden.unfilteredTotal, 'only what is counted');
    // Its type is still offered in the panel, so it can be turned back on.
    Set<String> offered = new Set<String>();
    for (TimeDriveController.TypeCount t : hidden.types) {
      offered.add(t.type);
    }
    Assert.isTrue(offered.contains('task'), 'still listed');
    Assert.isTrue(offered.contains('case'));
  }

  @IsTest
  static void dateFieldsThatAcceptDateFunctionsAreGroupedByTheWeekOnTheServer() {
    // Birthdate is a Date field that takes CALENDAR_YEAR() and WEEK_IN_YEAR(),
    // so by week it is grouped there (not counted by day and rolled up);
    // Task.ActivityDate is the one that can't be, and keeps the roll-up.
    Id customer = contactId();
    Date day = Date.today().addDays(-10);
    update new Contact(Id = customer, Birthdate = day);
    List<Time_Drive_Source__mdt> many = new List<Time_Drive_Source__mdt>();
    for (Integer i = 0; i < 5; i++) {
      Time_Drive_Source__mdt birthdays = source('Birthdays_' + i, 'Contact', 'Birthdate', 'Id');
      birthdays.Max_Records__c = 1;
      many.add(birthdays);
    }
    TimeDriveConfig.testSources = many;
    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, '10', '10');
    Assert.areEqual('week', summary.unit);
    Assert.isTrue(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
    Assert.areEqual(1, summary.days.size(), 'one week has the date');
    Assert.areEqual(TimeDriveContext.periodKey(day, 'week'), summary.days[0].key);
    Assert.areEqual(5, summary.days[0].count, 'once for each of the five sources');
  }

  @IsTest
  static void taskActivityDatesCountByWeekToo() {
    // ActivityDate takes no date functions (CALENDAR_YEAR, WEEK_IN_YEAR), so
    // by week it's counted by day and rolled up, never read as rows.
    Id customer = contactId();
    Date today = Date.today();
    // The setup's tasks may share today's week, depending on the date: leave only these.
    delete [SELECT Id FROM Task];
    insert new List<Task>{
      new Task(WhoId = customer, Subject = 'A', ActivityDate = today, Status = 'Completed'),
      new Task(WhoId = customer, Subject = 'B', ActivityDate = today, Status = 'Completed'),
      new Task(WhoId = customer, Subject = 'C', ActivityDate = today.addDays(-400), Status = 'Completed')
    };
    List<Time_Drive_Source__mdt> many = new List<Time_Drive_Source__mdt>();
    for (Integer i = 0; i < 5; i++) {
      Time_Drive_Source__mdt tasks = source('Tasks_' + i, 'Task', 'ActivityDate', 'WhoId');
      tasks.Max_Records__c = 1;
      many.add(tasks);
    }
    TimeDriveConfig.testSources = many;
    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(customer, null, null, '10', '10');
    Assert.areEqual('week', summary.unit);
    Assert.isTrue(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
    Map<String, Integer> byWeek = new Map<String, Integer>();
    for (TimeDriveController.DaySummary d : summary.days) {
      byWeek.put(d.key, d.count);
    }
    Assert.areEqual(10, byWeek.get(TimeDriveContext.periodKey(today, 'week')), 'two tasks, five sources');
    Assert.areEqual(5, byWeek.get(TimeDriveContext.periodKey(today.addDays(-400), 'week')));
  }

  @IsTest
  static void data360CountsRunInDataSpaceSql() {
    Map<String, Schema.SObjectType> objects = new Map<String, Schema.SObjectType>{
      'ssot__individual__dlm' => Contact.SObjectType,
      'ssot__emailengagement__dlm' => Contact.SObjectType
    };
    Time_Drive_Source__mdt email = data360Sources()[0];
    email.Data_Space__c = 'timedrive';
    StubSql stub = new StubSql(
      new List<List<Object>>{ new List<Object>{ '2026-10-12', 14, 3 }, new List<Object>{ '2026-10-13', 9, 1200 } }
    );
    TimeDriveData360Provider.sqlRunner = stub;
    TimeDriveContext context = new TimeDriveContext(
      contactId(),
      'Contact',
      Datetime.now().addDays(-30),
      email,
      null,
      new List<String>()
    );
    context.until = Datetime.now();

    List<TimeDriveContext.DayCount> counts = new TimeDriveData360Provider().countDays(context, 'hour', objects);
    Assert.areEqual(2, counts.size());
    Assert.areEqual('2026-10-13', counts[1].dayKey);
    Assert.areEqual(9, counts[1].hour);
    Assert.areEqual(1200, counts[1].count);
    Assert.areEqual('timedrive', stub.dataSpace);
    Assert.isTrue(stub.sql.contains('COUNT(*)'), stub.sql);
    Assert.isTrue(stub.sql.contains('GROUP BY'), stub.sql);
    Assert.isTrue(stub.sql.contains('AT TIME ZONE \'' + UserInfo.getTimeZone().getID() + '\''), stub.sql);
    Assert.isTrue(stub.sql.contains('\'' + String.valueOf(contactId()) + '\''), 'the Contact\'s Individual Id');
    Assert.areEqual('Data 360 · Contact', context.sourceLabel);
  }

  @IsTest
  static void data360SourcesThatCantBeCountedAreReadAsRows() {
    // No Data 360 here: the count fails, so the sources are read as rows,
    // which says why.
    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(contactId(), null, null, null, null);
    Assert.isTrue(summary.total > 0, 'CRM events still count');
    if (!Schema.getGlobalDescribe().containsKey('ssot__individual__dlm')) {
      Assert.isFalse(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
    }
  }

  private class StubSql implements TimeDriveData360Provider.SqlRunner {
    List<List<Object>> rows;
    String sql;
    String dataSpace;

    StubSql(List<List<Object>> rows) {
      this.rows = rows;
    }

    /**
     * Records the query and answers with the canned rows.
     * @param sql The query it was asked to run.
     * @param dataSpace The data space it was asked to run in.
     * @return The rows the stub was built with.
     */
    public List<List<Object>> run(String sql, String dataSpace) {
      this.sql = sql;
      this.dataSpace = dataSpace;
      return rows;
    }
  }

  private static TimeDriveController.EngagementEvent event(String id, String type, String day, Datetime at) {
    TimeDriveController.EngagementEvent e = new TimeDriveController.EngagementEvent(
      id,
      type,
      'Marketing',
      'Title',
      'Subtitle',
      at
    );
    e.dayKey = day;
    return e;
  }

  @IsTest
  static void data360SourcesWithoutData360ShowCrmEventsAndSayWhy() {
    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(contactId());
    Assert.areEqual(2, countOf(result, 'purchase'), 'Salesforce sources still load');
    Assert.areEqual(0, countOf(result, 'email'), 'no Data 360 engagement here');
    if (!Schema.getGlobalDescribe().containsKey('ssot__individual__dlm')) {
      Assert.isFalse(result.warnings.isEmpty(), 'explains that Data 360 is missing');
    }
  }

  @IsTest
  static void noContactGivesAnEmptyTimeline() {
    Assert.isTrue(TimeDriveController.getEvents(null).events.isEmpty());
  }

  @IsTest
  static void data360ActionsReadNaturally() {
    Assert.areEqual('opened', TimeDriveData360Provider.actionText('Open'));
    Assert.areEqual('page view', TimeDriveData360Provider.actionText('Page View'));
    Assert.areEqual('Bounce', TimeDriveData360Provider.actionText('Bounce'));
    Assert.isNull(TimeDriveData360Provider.actionText(null));
  }

  @IsTest
  static void identityLinksFallBackToTheContactsOwnIndividual() {
    Id customer = contactId();
    List<String> warnings = new List<String>();
    TimeDriveData360Provider.testSetting = new Time_Drive_Setting__mdt(
      Identity_Link_Object__c = 'UnifiedLinkssotIndividualTimeDrive__dlm'
    );
    Set<String> ids = TimeDriveData360Provider.individualIdsFor(
      customer,
      new Map<String, Schema.SObjectType>(),
      new TimeDriveContext(customer, 'Contact', Datetime.now(), null, null, warnings)
    );
    Assert.isTrue(ids.contains(String.valueOf(customer)));
    Assert.areEqual(1, warnings.size());
    Assert.isTrue(warnings[0].contains('UnifiedLinkssotIndividualTimeDrive__dlm'), 'names the configured link object');
  }

  @IsTest
  static void identityLinksAreFoundByTheirRulesetsName() {
    // The link DMO set isn't there; identity resolution's ruleset one is.
    TimeDriveData360Provider.testDmoNames = new List<String>{
      'Reservation__dlm',
      'UnifiedLinkssotIndividualCcid__dlm',
      'UnifiedLinkssotContactPointEmailCcid__dlm'
    };
    Map<String, Schema.SObjectType> objects = new Map<String, Schema.SObjectType>{
      'unifiedlinkssotindividualccid__dlm' => Contact.SObjectType,
      'unifiedlinkssotcontactpointemailccid__dlm' => Contact.SObjectType
    };
    Assert.areEqual(
      'UnifiedLinkssotIndividualCcid__dlm',
      TimeDriveData360Provider.linkObjectIn(objects, 'IndividualIdentityLink__dlm', 'default')
    );
    // The one set wins when it's there.
    objects.put('individualidentitylink__dlm', Contact.SObjectType);
    Assert.areEqual(
      'IndividualIdentityLink__dlm',
      TimeDriveData360Provider.linkObjectIn(objects, 'IndividualIdentityLink__dlm', 'default')
    );
    TimeDriveData360Provider.testDmoNames = new List<String>();
    Assert.isNull(TimeDriveData360Provider.linkObjectIn(new Map<String, Schema.SObjectType>(), 'Nope__dlm', null));
  }

  @IsTest
  static void customDataModelObjectsUseTheirOwnIdAndDates() {
    Id customer = contactId();
    TimeDriveContext context = new TimeDriveContext(
      customer,
      'Contact',
      Datetime.now(),
      null,
      null,
      new List<String>()
    );
    context.source = new Time_Drive_Source__mdt(Kind__c = 'Data 360', Object_Name__c = 'Reservation__dlm');
    // No ssot__Id__c on the object: its Id keys the rows.
    Map<String, Schema.SObjectField> fields = Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .fields.getMap();
    Assert.areEqual('Id', TimeDriveData360Provider.fitIdField(context, fields).Id_Field__c);
    Assert.areEqual('Id', context.idField());
    // An Id Field that's set is kept.
    context.source = new Time_Drive_Source__mdt(Kind__c = 'Data 360', Id_Field__c = 'Reservation_ID__c');
    Assert.areEqual('Reservation_ID__c', TimeDriveData360Provider.fitIdField(context, fields).Id_Field__c);

    // A Date field is compared with days; a Date/Time one with instants.
    Assert.isTrue(TimeDriveData360Provider.isDate(fields, 'Birthdate'));
    Assert.isFalse(TimeDriveData360Provider.isDate(fields, 'CreatedDate'));
    Datetime at = Datetime.newInstance(2026, 3, 4, 10, 0, 0);
    Assert.areEqual('DATE \'2026-03-04\'', TimeDriveData360Provider.bound(at, true));
    Assert.isTrue(TimeDriveData360Provider.bound(at, false).startsWith('TIMESTAMP '));
  }

  @IsTest
  static void data360RowsAreReadForTheSpansAskedOnly() {
    // A page's quiet days, not the whole window: Max Records can't cut off
    // days further back.
    Datetime a = Datetime.newInstance(2026, 1, 5, 0, 0, 0);
    Datetime b = Datetime.newInstance(2026, 1, 5, 23, 59, 59);
    Datetime c = Datetime.newInstance(2026, 3, 9, 0, 0, 0);
    List<TimeDriveController.TimeWindow> spans = new List<TimeDriveController.TimeWindow>{
      new TimeDriveController.TimeWindow(a, b),
      new TimeDriveController.TimeWindow(c, null)
    };
    Map<String, Object> binds = new Map<String, Object>();
    Assert.areEqual(
      '(Check_in_Date__c >= :since0 AND Check_in_Date__c <= :until0) OR (Check_in_Date__c >= :since1)',
      TimeDriveData360Provider.within('Check_in_Date__c', spans, true, binds)
    );
    Assert.areEqual(Date.newInstance(2026, 1, 5), binds.get('since0'), 'a Date field gets days');
    Assert.areEqual(Date.newInstance(2026, 1, 5), binds.get('until0'));
    Assert.areEqual(Date.newInstance(2026, 3, 9), binds.get('since1'));
    Assert.isFalse(binds.containsKey('until1'));

    binds.clear();
    TimeDriveData360Provider.within('ssot__EngagementDateTm__c', spans, false, binds);
    Assert.areEqual(a, binds.get('since0'), 'a Date/Time field gets instants');
  }

  @IsTest
  static void anAccountsData360RecordsMatchItsId() {
    Account acme = new Account(Name = 'Acme');
    insert acme;
    List<String> warnings = new List<String>();
    Set<String> ids = TimeDriveData360Provider.individualIdsFor(
      acme.Id,
      new Map<String, Schema.SObjectType>(),
      new TimeDriveContext(acme.Id, 'Account', Datetime.now(), null, null, warnings)
    );
    Assert.areEqual(new Set<String>{ String.valueOf(acme.Id), String.valueOf(acme.Id).left(15) }, ids);
    Assert.isTrue(warnings.isEmpty(), 'no identity links to follow for an account');
  }

  @IsTest
  static void unreadableData360ObjectsBecomeWarnings() {
    // A data model that claims Data 360, the identity link and every
    // engagement DMO exist; querying them fails here, which must turn into
    // one warning each rather than an exception.
    Map<String, Schema.SObjectType> objects = new Map<String, Schema.SObjectType>{
      'ssot__individual__dlm' => Contact.SObjectType,
      'individualidentitylink__dlm' => Contact.SObjectType
    };
    List<Time_Drive_Source__mdt> dmos = data360Sources();
    for (Time_Drive_Source__mdt s : dmos) {
      objects.put(s.Object_Name__c.toLowerCase(), Contact.SObjectType);
    }
    List<String> warnings = new List<String>();
    List<TimeDriveController.Problem> problems = new List<TimeDriveController.Problem>();
    TimeDriveData360Provider provider = new TimeDriveData360Provider();
    for (Time_Drive_Source__mdt s : dmos) {
      TimeDriveContext context = new TimeDriveContext(
        contactId(),
        'Contact',
        Datetime.now().addDays(-30),
        s,
        null,
        warnings
      );
      context.problems = problems;
      Assert.isTrue(provider.getRows(context, objects).isEmpty());
      Assert.areEqual('Data 360 · Contact', context.sourceLabel);
    }
    // Reads that fail are problems, named but never with the exception's text.
    Assert.isTrue(warnings.isEmpty(), String.join(warnings, ' | '));
    Assert.areEqual(7, problems.size(), 'identity links once, plus six engagement objects');
    Assert.areEqual('Identity links', problems[0].source);
    for (TimeDriveController.Problem p : problems) {
      Assert.areEqual('access', p.kind, p.source + ' reads fields this org lacks');
    }
  }

  @IsTest
  static void data360ObjectsMissingFromTheModelAreNamed() {
    List<String> warnings = new List<String>();
    TimeDriveData360Provider provider = new TimeDriveData360Provider();
    for (Time_Drive_Source__mdt s : data360Sources()) {
      provider.getRows(
        new TimeDriveContext(contactId(), 'Contact', Datetime.now(), s, null, warnings),
        new Map<String, Schema.SObjectType>{ 'ssot__individual__dlm' => Contact.SObjectType }
      );
    }
    Assert.areEqual(6, warnings.size(), String.join(warnings, ' | '));
    Assert.isTrue(warnings[0].contains('ssot__EmailEngagement__dlm'));

    // Without Data 360 at all, one warning however many sources ask.
    warnings.clear();
    for (Time_Drive_Source__mdt s : data360Sources()) {
      provider.getRows(
        new TimeDriveContext(contactId(), 'Contact', Datetime.now(), s, null, warnings),
        new Map<String, Schema.SObjectType>()
      );
    }
    Assert.areEqual(1, warnings.size());
  }

  @IsTest
  static void data360SourcesDefaultTheirFieldsAndProvider() {
    Time_Drive_Source__mdt s = data360Sources()[0];
    TimeDriveContext context = new TimeDriveContext(contactId(), 'Contact', Datetime.now(), s, null, null);
    Assert.areEqual('ssot__EngagementDateTm__c', context.dateField());
    Assert.areEqual('ssot__Id__c', context.idField());
    Assert.isNull(context.recordIdField());
    Assert.isTrue(TimeDriveConfig.providerFor(s, new List<String>()) instanceof TimeDriveData360Provider);
  }

  @IsTest
  static void offersTheRecordsActivityActions() {
    List<TimeDriveController.ActivityAction> actions = TimeDriveController.getActivityActions(contactId());
    // Whatever the layout offers, each opens by API name and has an icon.
    for (TimeDriveController.ActivityAction a : actions) {
      Assert.isNotNull(a.apiName);
      Assert.isTrue(a.icon.contains(':'), a.icon);
    }
    Assert.isTrue(TimeDriveController.getActivityActions(null).isEmpty());
    Assert.areEqual(
      'action:new_task',
      TimeDriveController.iconName('https://x.my.salesforce.com/img/icon/t4v35/action/new_task_120.png')
    );
    Assert.areEqual(
      'action:log_a_call',
      TimeDriveController.iconName('https://x.my.salesforce.com/img/icon/t4v35/action/log_a_call')
    );
    Assert.areEqual('utility:add', TimeDriveController.iconName(null));
  }

  @IsTest
  static void templatesFillTokensAndDropBlankParts() {
    Opportunity o = [
      SELECT Id, Amount, Account.Name, Description
      FROM Opportunity
      WHERE StageName = 'Closed Won'
      LIMIT 1
    ];
    TimeDriveRow row = new TimeDriveRow(o);
    Assert.areEqual(
      'Ada Catering Co · ' + TimeDrivePlotter.format(3500, null, row, 'Amount'),
      TimeDrivePlotter.fill('{Account.Name} · {Amount}', row)
    );
    // No description: its part drops out.
    Assert.areEqual('Ada Catering Co', TimeDrivePlotter.fill('{Account.Name} · {Description}', row));
    Assert.areEqual(
      new Set<String>{ 'Subject', 'Account.Name' },
      TimeDrivePlotter.tokens('{Subject} at {Account.Name}')
    );
    Assert.isNull(TimeDrivePlotter.fill(null, row));
    // A title whose fields are all blank shows their labels instead.
    String descriptionLabel = Opportunity.Description.getDescribe().getLabel();
    Assert.areEqual('[' + descriptionLabel + ']', TimeDrivePlotter.title('{Description}', row));
    Assert.areEqual('Ada Catering Co', TimeDrivePlotter.title('{Account.Name} · {Description}', row));

    // Map rows from Apex providers fill the same way, keys in any case.
    TimeDriveRow mapRow = new TimeDriveRow(new Map<String, Object>{ 'Points' => 120, 'Tier' => null });
    Assert.areEqual('Earned 120 points', TimeDrivePlotter.fill('Earned {points} points · {Tier}', mapRow));
    Assert.areEqual('$12.50', TimeDrivePlotter.format(12.5, 'Currency', mapRow, 'Points'));
    Assert.areEqual(
      Date.newInstance(2026, 3, 4).format(),
      TimeDrivePlotter.format(Datetime.newInstance(2026, 3, 4, 9, 0, 0), 'Date', mapRow, 'x')
    );
    Assert.areEqual('Yes', TimeDrivePlotter.format(true, null, mapRow, 'x'));

    // Numbers lose floating-point noise and trailing zeros.
    Assert.areEqual('2713.31', TimeDrivePlotter.format(2713.3099999999999, null, mapRow, 'x'));
    Assert.areEqual('2713.31', TimeDrivePlotter.format(Double.valueOf('2713.31'), null, mapRow, 'x'));
    Assert.areEqual('2', TimeDrivePlotter.format(2.000000, null, mapRow, 'x'));
    Assert.areEqual('1500', TimeDrivePlotter.format(1500, null, mapRow, 'x'));
    // A field's own decimal places win: Probability has none.
    Opportunity deal = new Opportunity(Probability = 33.3333);
    Assert.areEqual('33', TimeDrivePlotter.format(33.3333, null, new TimeDriveRow(deal), 'Probability'));
  }

  @IsTest
  static void apexSourcesArePlottedFromTheirRecord() {
    Time_Drive_Source__mdt loyalty = new Time_Drive_Source__mdt(
      DeveloperName = 'Loyalty',
      Label = 'Loyalty',
      Active__c = true,
      Sequence__c = 50,
      Parent_Object__c = 'Contact',
      Kind__c = 'Apex',
      Provider_Class__c = 'TimeDriveExampleProvider',
      Object_Name__c = 'Loyalty',
      Date_Field__c = 'EarnedAt',
      Record_Id_Field__c = 'OrderId',
      Title__c = 'Earned {Points} points',
      Subtitle__c = '{Reason}',
      Event_Type__c = 'loyalty',
      Event_Label__c = 'Loyalty points',
      Category__c = 'Commerce',
      Icon__c = 'utility:reward',
      Icon_Colour__c = '#7A4CB8',
      Use_Compact_Layout__c = true
    );
    Time_Drive_Source__mdt orders = TimeDriveTestData.source('Order_Placed');
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ orders, loyalty };
    TimeDriveConfig.testDetailFields = new Map<String, List<Time_Drive_Detail_Field__mdt>>{
      'Loyalty' => new List<Time_Drive_Detail_Field__mdt>{
        new Time_Drive_Detail_Field__mdt(Label = 'Points', Field__c = 'Points', Format__c = 'Number'),
        new Time_Drive_Detail_Field__mdt(Label = null, Field__c = 'Balance')
      }
    };

    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(contactId());
    List<TimeDriveController.EngagementEvent> points = new List<TimeDriveController.EngagementEvent>();
    for (TimeDriveController.EngagementEvent e : result.events) {
      if (e.type == 'loyalty') {
        points.add(e);
      }
    }
    Assert.areEqual(countOf(result, 'purchase'), points.size(), 'one loyalty event per order');
    TimeDriveController.EngagementEvent latest = points[0];
    Assert.isTrue(latest.title.startsWith('Earned '), latest.title);
    Assert.areEqual('utility:reward', latest.icon);
    Assert.areEqual('Loyalty points', latest.typeLabel);
    Assert.isNotNull(latest.recordId, 'links to the order through Record Id Field');
    Assert.areEqual('Points', latest.details[0].label);
    Assert.areEqual('Balance', latest.details[1].label, 'blank labels fall back to the field name');
    Assert.isTrue(result.warnings.isEmpty(), String.join(result.warnings, ' | '));
  }

  @IsTest
  static void theLegendNameIsTranslatedTypedOrTheObjects() {
    Time_Drive_Source__mdt s = source('Follow_Ups', 'Task', 'ActivityDate', 'WhoId');
    s.Kind__c = 'Salesforce';
    // Blank: the object's plural name, which Salesforce translates.
    Assert.areEqual(
      Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
      TimeDriveConfig.legendLabel(s)
    );
    // A custom label: its value in the viewer's language.
    s.Event_Label__c = '$Label.Time_Drive_Example_Legend';
    Assert.areEqual(System.Label.get('', 'Time_Drive_Example_Legend'), TimeDriveConfig.legendLabel(s));
    Assert.areEqual('Follow-ups', TimeDriveConfig.customLabel('Time_Drive_Example_Legend'));
    // Words: as typed. A label that doesn't exist: the source's own name.
    s.Event_Label__c = 'Follow-ups';
    Assert.areEqual('Follow-ups', TimeDriveConfig.legendLabel(s));
    s.Event_Label__c = '$Label.No_Such_Label_Here';
    Assert.areEqual('Follow_Ups', TimeDriveConfig.legendLabel(s));
    Assert.isNull(TimeDriveConfig.customLabel('No_Such_Label_Here'));
  }

  @IsTest
  static void eventsAContactIsOnPlotThroughEventRelation() {
    Id customer = contactId();
    Contact other = new Contact(LastName = 'Organiser');
    insert other;
    // An event about someone else that the Contact is invited to.
    Event meeting = new Event(
      WhoId = other.Id,
      Subject = 'Menu tasting',
      StartDateTime = Datetime.now().addDays(-2),
      EndDateTime = Datetime.now().addDays(-2).addHours(1)
    );
    insert meeting;
    insert new EventRelation(EventId = meeting.Id, RelationId = customer);
    Time_Drive_Source__mdt events = source('Events', 'Event', 'StartDateTime', null);
    events.Parent_Field__c = null;
    events.Junction_Object__c = 'EventRelation';
    events.Junction_Parent_Field__c = 'RelationId';
    events.Junction_Record_Field__c = 'EventId';
    events.Title__c = '{Subject}';
    events.Event_Type__c = 'meeting';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ events };

    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(customer);
    Assert.areEqual(1, countOf(result, 'meeting'), String.join(result.warnings, ' | '));
    Assert.areEqual('Menu tasting', result.events[0].title);
  }

  @IsTest
  static void anAccountPageHasItsOwnSources() {
    Account acme = new Account(Name = 'Acme');
    insert acme;
    insert new Case(AccountId = acme.Id, Subject = 'Login trouble');
    Time_Drive_Source__mdt cases = source('Account_Cases', 'Case', 'CreatedDate', 'AccountId');
    cases.Parent_Object__c = 'Account';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ cases };

    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(acme.Id);
    Assert.areEqual(1, result.events.size(), String.join(result.warnings, ' | '));
    Assert.areEqual('case', result.events[0].type);
    // A business account isn't a person account (nor is any account where
    // person accounts are off).
    Assert.isNull(TimeDriveController.personContactOf(acme.Id));
    Assert.isNull(TimeDriveController.personContactOf(contactId()));
  }

  @IsTest
  static void aPersonAccountsContactLinksMatchItsOwnContact() {
    Id account = fakeId('001', 1);
    Id person = fakeId('003', 1);
    TimeDriveContext context = new TimeDriveContext(account, 'PersonAccount', null, null, null, null);
    context.personContactId = person;
    Assert.areEqual(person, context.parentIdFor(Case.ContactId.getDescribe()), 'a Contact lookup');
    Assert.areEqual(person, context.parentIdFor(Task.WhoId.getDescribe()), 'a Name lookup, Contact or Lead');
    Assert.areEqual(account, context.parentIdFor(Case.AccountId.getDescribe()), 'an Account lookup');
    Assert.areEqual(person, context.contactId());
  }

  @IsTest
  static void aClickCanPointAtARelatedRecord() {
    Time_Drive_Source__mdt s = source('Members', 'CampaignMember', 'CreatedDate', 'ContactId');
    s.Record_Id_Field__c = 'CampaignId';
    Id member = fakeId('00v', 1);
    Id campaign = fakeId('701', 1);
    List<TimeDriveRow> rows = new List<TimeDriveRow>{
      new TimeDriveRow(
        new Map<String, Object>{ 'Id' => member, 'CampaignId' => campaign, 'CreatedDate' => Datetime.now() }
      )
    };

    TimeDriveController.EngagementEvent e = TimeDrivePlotter.plot(
      new TimeDriveContext(null, 'Contact', null, s, null, null),
      rows
    )[0];
    Assert.areEqual(campaign, e.recordId, 'a click opens the Campaign');

    // Left blank, it is the item's own record.
    s.Record_Id_Field__c = null;
    e = TimeDrivePlotter.plot(new TimeDriveContext(null, 'Contact', null, s, null, null), rows)[0];
    Assert.areEqual(member, e.recordId);
  }

  @IsTest
  static void anOpenedItemShowsTheDetailFieldsChosen() {
    Time_Drive_Source__mdt cases = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    TimeDriveConfig.testDetailFields = new Map<String, List<Time_Drive_Detail_Field__mdt>>{
      'Cases' => new List<Time_Drive_Detail_Field__mdt>{
        new Time_Drive_Detail_Field__mdt(Field__c = 'Status'),
        new Time_Drive_Detail_Field__mdt(Label = 'Account', Field__c = 'Account.Name')
      }
    };
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(
      new TimeDriveSoqlProvider(),
      new TimeDriveContext(contactId(), 'Contact', Datetime.now().addDays(-1), cases, null, null)
    );
    Assert.areEqual(1, events.size());
    Assert.areEqual('Status', events[0].details[0].label, 'blank labels use the field label');
    Assert.areEqual('New', events[0].details[0].value);
    Assert.areEqual('Salesforce · Case', events[0].sourceLabel);
  }

  @IsTest
  static void detailFieldsWithNoLabelOfTheirOwnUseTheFieldsOwnLabel() {
    Time_Drive_Source__mdt tasks = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    TimeDriveConfig.testDetailFields = new Map<String, List<Time_Drive_Detail_Field__mdt>>{
      'Tasks' => new List<Time_Drive_Detail_Field__mdt>{
        // Setup saves "no label of its own" as Label = the field.
        new Time_Drive_Detail_Field__mdt(Label = 'Description', Field__c = 'Description'),
        new Time_Drive_Detail_Field__mdt(Label = 'Who.Name', Field__c = 'Who.Name'),
        new Time_Drive_Detail_Field__mdt(Label = 'Status', Field__c = 'Status'),
        new Time_Drive_Detail_Field__mdt(Label = 'Notes', Field__c = 'Priority')
      }
    };
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(
      new TimeDriveSoqlProvider(),
      new TimeDriveContext(contactId(), 'Contact', Datetime.now().addDays(-30), tasks, null, null)
    );
    TimeDriveController.EngagementEvent padThai;
    for (TimeDriveController.EngagementEvent e : events) {
      if (!e.details.isEmpty() && e.details[0].value == 'Pad thai and spring rolls') {
        padThai = e;
      }
    }
    Assert.isNotNull(padThai);
    Assert.areEqual(Task.Description.getDescribe().getLabel(), padThai.details[0].label);
    Assert.areEqual(
      Task.WhoId.getDescribe().getLabel().removeEnd(' ID'),
      padThai.details[1].label,
      'a name through a lookup reads as the lookup, without the ID Apex adds'
    );
    Assert.areEqual('Ada Shift', padThai.details[1].value);
    Assert.areEqual(Task.Status.getDescribe().getLabel(), padThai.details[2].label);
    Assert.areEqual('Notes', padThai.details[3].label, 'a label of its own wins');
  }

  @IsTest
  static void aHighlightMarksItemsWhoseCheckboxIsChecked() {
    Id customer = contactId();
    insert new List<Task>{
      new Task(
        WhoId = customer,
        Subject = 'Urgent',
        Status = 'Open',
        Priority = 'High',
        ActivityDate = Date.today().addDays(-1)
      ),
      new Task(
        WhoId = customer,
        Subject = 'Routine',
        Status = 'Open',
        Priority = 'Normal',
        ActivityDate = Date.today().addDays(-1)
      )
    };
    Time_Drive_Source__mdt tasks = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    tasks.Title__c = '{Subject}';
    TimeDriveConfig.testHighlights = new Map<String, List<Time_Drive_Highlight__mdt>>{
      'Tasks' => new List<Time_Drive_Highlight__mdt>{
        // A text field is no checkbox: left out. One highlight a source: the second is too.
        new Time_Drive_Highlight__mdt(Field__c = 'Subject', Icon__c = 'dot'),
        new Time_Drive_Highlight__mdt(Field__c = 'IsHighPriority', Icon__c = 'utility:priority', Colour__c = '#C23934'),
        new Time_Drive_Highlight__mdt(Field__c = 'IsClosed', Icon__c = 'dot', Colour__c = '#2E844A')
      }
    };
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(
      new TimeDriveSoqlProvider(),
      new TimeDriveContext(customer, 'Contact', Datetime.now().addDays(-30), tasks, null, null)
    );
    TimeDriveController.EngagementEvent urgent;
    TimeDriveController.EngagementEvent routine;
    for (TimeDriveController.EngagementEvent e : events) {
      if (e.title == 'Urgent') {
        urgent = e;
      } else if (e.title == 'Routine') {
        routine = e;
      }
    }
    Assert.isNotNull(urgent);
    Assert.areEqual(1, urgent.flags.size());
    Assert.areEqual('utility:priority', urgent.flags[0].icon);
    Assert.areEqual('#C23934', urgent.flags[0].colour);
    Assert.areEqual(Task.IsHighPriority.getDescribe().getLabel(), urgent.flags[0].text);
    Assert.isNull(routine.flags, 'unchecked: no icon');
  }

  @IsTest
  static void aBusyDayKeepsATypeWithOneItemAsItself() {
    List<TimeDriveController.EngagementEvent> events = new List<TimeDriveController.EngagementEvent>();
    Datetime at = Datetime.newInstance(2026, 3, 3, 10, 0, 0);
    for (Integer i = 0; i < 4; i++) {
      TimeDriveController.EngagementEvent e = new TimeDriveController.EngagementEvent(
        't' + i,
        'task',
        'Sales',
        'Task ' + i,
        null,
        at.addMinutes(i)
      );
      e.dayKey = '2026-03-03';
      events.add(e);
    }
    TimeDriveController.EngagementEvent opp = new TimeDriveController.EngagementEvent(
      'o1',
      'opportunity',
      'Sales',
      'Opp',
      null,
      at
    );
    opp.dayKey = '2026-03-03';
    events.add(opp);
    List<TimeDriveController.EngagementEvent> out = TimeDriveController.groupBusyDays(events, 3);
    Integer groups = 0;
    Boolean oppItself = false;
    for (TimeDriveController.EngagementEvent e : out) {
      groups += e.grouped ? 1 : 0;
      oppItself = oppItself || (e.type == 'opportunity' && !e.grouped && e.title == 'Opp');
    }
    Assert.areEqual(1, groups, 'the four tasks group');
    Assert.isTrue(oppItself, 'the single opportunity stays an item');
  }

  @IsTest
  static void daysSayWhatTheUserMayDoWithEachRecord() {
    Task task = new Task(WhoId = contactId(), Subject = 'Call back', Status = 'Open');
    insert task;
    TimeDriveController.EngagementEvent withRecord = new TimeDriveController.EngagementEvent(
        'a',
        'task',
        'Sales',
        'Call back',
        null,
        Datetime.now()
      )
      .record(task.Id);
    TimeDriveController.EngagementEvent noRecord = new TimeDriveController.EngagementEvent(
      'b',
      'email',
      'Marketing',
      'Opened',
      null,
      Datetime.now()
    );
    Integer before = Limits.getQueries();
    TimeDriveController.markRights(new List<TimeDriveController.EngagementEvent>{ withRecord, noRecord });
    Assert.areEqual(before, Limits.getQueries(), 'drawing the days asks nothing about the records');
    Assert.isTrue(withRecord.canEdit, 'the object allows edit');
    Assert.isTrue(withRecord.canDelete, 'the object allows delete');
    Assert.areEqual('Task', withRecord.objectLabel);
    Assert.isFalse(noRecord.canEdit, 'no record, no menu');
    Assert.isFalse(noRecord.canDelete);

    // What the record itself allows is asked for when its menu opens.
    TimeDriveController.RecordRights rights = TimeDriveController.getRights(task.Id);
    Assert.isTrue(rights.canEdit, 'the owner can edit');
    Assert.isTrue(rights.canDelete, 'the owner can delete');
    Assert.isFalse(TimeDriveController.getRights(null).canEdit);
  }

  @IsTest
  static void theTimelineComesWithTheDaysItOpensOn() {
    Id customer = contactId();
    Date today = Date.today();
    // The setup's tasks would share days with these: leave only these.
    delete [SELECT Id FROM Task];
    insert new List<Task>{
      new Task(WhoId = customer, Subject = 'Now', ActivityDate = today, Status = 'Completed'),
      new Task(WhoId = customer, Subject = 'Recent', ActivityDate = today.addDays(-3), Status = 'Completed'),
      new Task(WhoId = customer, Subject = 'Older', ActivityDate = today.addDays(-40), Status = 'Completed')
    };
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source('Tasks', 'Task', 'ActivityDate', 'WhoId') };
    String todayKey = String.valueOf(today);
    String oldest = String.valueOf(today.addDays(-40));

    // Opening on today, newest first: today heads the page; the days under it
    // follow (up to a page), and every item comes with its summary.
    TimeDriveController.TimelineLoad load = TimeDriveController.getTimeline(
      customer,
      null,
      null,
      '0.5',
      null,
      'Today',
      true,
      false,
      7
    );
    Assert.areEqual(3, load.summary.total);
    Assert.areEqual(new List<String>{ todayKey, String.valueOf(today.addDays(-3)), oldest }, load.keys);
    Assert.areEqual(3, load.events.size());
    for (TimeDriveController.EngagementEvent e : load.events) {
      Assert.isTrue(new Set<String>(load.keys).contains(e.dayKey), 'every item belongs to a period it names');
    }

    // The same items as asking for those days separately.
    List<TimeDriveController.EngagementEvent> separately = TimeDriveController.getDays(
      customer,
      null,
      null,
      '0.5',
      null,
      load.keys,
      new List<String>()
    );
    Assert.areEqual(separately.size(), load.events.size());

    // Opening on the earliest item: that period comes first among the keys.
    load = TimeDriveController.getTimeline(customer, null, null, '0.5', null, 'Earliest item', true, false, 1);
    Assert.areEqual(new List<String>{ oldest }, load.keys);
    Assert.areEqual(1, load.events.size());

    // Across (oldest first), centred on today: the periods either side of it.
    load = TimeDriveController.getTimeline(customer, null, null, '0.5', null, 'Today', false, true, 3);
    Assert.isTrue(load.keys.contains(todayKey));
    Assert.isTrue(load.events.size() > 0);

    // A summary that used up much of the request leaves the days to a request of their own.
    TimeDriveController.testBudgetSpent = true;
    load = TimeDriveController.getTimeline(customer, null, null, '0.5', null, 'Today', true, false, 7);
    Assert.areEqual(3, load.summary.total);
    Assert.isTrue(load.keys.isEmpty());
    Assert.isTrue(load.events.isEmpty());
    TimeDriveController.testBudgetSpent = null;

    // A count of none: the summary alone.
    load = TimeDriveController.getTimeline(customer, null, null, '0.5', null, 'Today', true, false, 0);
    Assert.areEqual(3, load.summary.total);
    Assert.isTrue(load.events.isEmpty());

    // No page asked for, no rows read: just what getSummary answers.
    TimeDriveController.TimelineLoad none = TimeDriveController.getTimeline(
      null,
      null,
      null,
      '0.5',
      null,
      'Today',
      true,
      false,
      7
    );
    Assert.isTrue(none.keys.isEmpty());
    Assert.isTrue(none.events.isEmpty());
  }

  @IsTest
  static void anActivitySharedWithAnAccountsContactRollsUpToTheAccount() {
    if (TimeDriveConfig.sObjectType('TaskRelation') == null) {
      return; // Shared Activities is off in this org: nothing to roll up.
    }
    Account mine = new Account(Name = 'Mine');
    Account other = new Account(Name = 'Other');
    insert new List<Account>{ mine, other };
    Contact mineContact = new Contact(LastName = 'Mine', AccountId = mine.Id);
    Contact otherContact = new Contact(LastName = 'Other', AccountId = other.Id);
    insert new List<Contact>{ mineContact, otherContact };
    Date day = Date.today().addDays(-1);
    // Primary on this account (the account source has it); primary on another
    // account but shared with this one's contact (the shared source adds it);
    // and one of another account's alone (neither has it).
    Task onMine = new Task(WhoId = mineContact.Id, Subject = 'On mine', ActivityDate = day, Status = 'Completed');
    Task shared = new Task(WhoId = otherContact.Id, Subject = 'Shared', ActivityDate = day, Status = 'Completed');
    Task alone = new Task(WhoId = otherContact.Id, Subject = 'Alone', ActivityDate = day, Status = 'Completed');
    insert new List<Task>{ onMine, shared, alone };
    // By name: orgs without Shared Activities have no TaskRelation to compile against.
    SObject relation = TimeDriveConfig.sObjectType('TaskRelation').newSObject();
    relation.put('TaskId', shared.Id);
    relation.put('RelationId', mineContact.Id);
    relation.put('IsWhat', false);
    insert relation;

    Time_Drive_Source__mdt primary = source('Primary', 'Task', 'ActivityDate', 'AccountId');
    primary.Parent_Object__c = 'Account';
    primary.Title__c = '{Subject}';
    Time_Drive_Source__mdt sharedSource = source('Shared', 'Task', 'ActivityDate', null);
    sharedSource.Parent_Object__c = 'Account';
    sharedSource.Title__c = '{Subject}';
    sharedSource.Junction_Object__c = 'TaskRelation';
    sharedSource.Junction_Parent_Field__c = 'AccountId';
    sharedSource.Junction_Record_Field__c = 'TaskId';
    sharedSource.Filter__c = 'AccountId != :parentId';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ primary, sharedSource };

    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(mine.Id, null, null, '0.5', null);
    Assert.areEqual(2, summary.total, 'on the account, and shared with it: once each');
    List<TimeDriveController.EngagementEvent> events = TimeDriveController.getDays(
      mine.Id,
      null,
      null,
      '0.5',
      null,
      new List<String>{ String.valueOf(day) },
      new List<String>()
    );
    Set<String> titles = new Set<String>();
    for (TimeDriveController.EngagementEvent e : events) {
      titles.add(e.title);
    }
    Assert.areEqual(new Set<String>{ 'On mine', 'Shared' }, titles);
  }

  @IsTest
  static void badSourceRecordsWarnInsteadOfFailing() {
    Id customer = contactId();
    List<String> warnings = new List<String>();
    TimeDriveSoqlProvider provider = new TimeDriveSoqlProvider();
    List<Time_Drive_Source__mdt> broken = new List<Time_Drive_Source__mdt>{
      source('No_Object', 'Nope__c', 'CreatedDate', 'ContactId'),
      source('No_Field', 'Case', 'Nope__c', 'ContactId'),
      source('No_Link', 'Case', 'CreatedDate', null),
      source('Bad_Filter', 'Case', 'CreatedDate', 'ContactId')
    };
    broken[3].Filter__c = 'Nope__c = 1';
    List<TimeDriveController.Problem> problems = new List<TimeDriveController.Problem>();
    for (Time_Drive_Source__mdt s : broken) {
      TimeDriveContext context = new TimeDriveContext(
        customer,
        'Contact',
        Datetime.now().addDays(-30),
        s,
        null,
        warnings
      );
      context.problems = problems;
      List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(provider, context);
      Assert.isTrue(events.isEmpty());
    }
    // Records checked before querying get a configuration warning (a
    // missing object, field or link); a query that still fails (the bad
    // filter) is a problem, named with the kind of failure only.
    Assert.areEqual(3, warnings.size(), String.join(warnings, ' | '));
    Assert.areEqual(1, problems.size());
    Assert.areEqual('Bad_Filter', problems[0].source);
    for (TimeDriveController.Problem p : problems) {
      Assert.isFalse(p.source.contains('Nope__c'), 'no query text: ' + p.source);
    }

    Time_Drive_Source__mdt notAProvider = source('Not_A_Provider', 'Case', 'CreatedDate', 'ContactId');
    notAProvider.Provider_Class__c = 'TimeDriveConfig';
    Assert.isNull(TimeDriveConfig.providerFor(notAProvider, warnings));
    Time_Drive_Source__mdt apexWithoutClass = source('No_Class', 'Case', 'CreatedDate', 'ContactId');
    apexWithoutClass.Kind__c = 'Apex';
    Assert.isNull(TimeDriveConfig.providerFor(apexWithoutClass, warnings));
    Assert.areEqual(5, warnings.size());
  }

  @IsTest
  static void failuresReachTheClientAsAKindOnly() {
    QueryException missing = new QueryException();
    missing.setMessage('No such column \'Secret__c\' on entity \'Invoice__c\'');
    AuraHandledException failure = TimeDriveController.safeFailure(missing);
    Assert.areEqual('timedrive:access', failure.getMessage(), 'no query text or stack trace');

    Exception other = new DmlException();
    other.setMessage('Something odd');
    Assert.areEqual('unknown', TimeDriveController.kindOf(other));
    other.setMessage('Apex CPU time limit exceeded');
    Assert.areEqual('busy', TimeDriveController.kindOf(other));
  }

  @IsTest
  static void activeSourcesRunInSequence() {
    Time_Drive_Source__mdt later = source('Later', 'Case', 'CreatedDate', 'ContactId');
    later.Sequence__c = 20;
    Time_Drive_Source__mdt sooner = source('Sooner', 'Case', 'CreatedDate', 'ContactId');
    sooner.Sequence__c = 10;
    // A Data 360 source runs like any other.
    Time_Drive_Source__mdt dmo = source('Reservations', 'Reservation__dlm', 'Check_in_Date__c', 'Contact_ID__c');
    dmo.Kind__c = 'Data 360';
    dmo.Sequence__c = 15;
    Time_Drive_Source__mdt inactive = source('Inactive', 'Case', 'CreatedDate', 'ContactId');
    inactive.Active__c = false;
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ later, dmo, inactive, sooner };

    List<String> names = new List<String>();
    for (Time_Drive_Source__mdt s : TimeDriveConfig.sources('Contact')) {
      names.add(s.DeveloperName);
    }
    Assert.areEqual(new List<String>{ 'Sooner', 'Reservations', 'Later' }, names);
    Assert.isTrue(TimeDriveConfig.sources('Account').isEmpty());
  }

  @IsTest
  static void configuredStylingReachesTheEvents() {
    TimeDriveController.TimelineResult result = TimeDriveController.getEvents(contactId());
    Boolean sawCase = false;
    for (TimeDriveController.EngagementEvent e : result.events) {
      if (e.type == 'case') {
        sawCase = true;
        Assert.areEqual('utility:case', e.icon);
        Assert.areEqual('#1F7A8C', e.iconColour);
        Assert.areEqual('Case updates', e.typeLabel);
      }
    }
    Assert.isTrue(sawCase);
  }

  @IsTest
  static void viewAllPagesThroughEverySourceOfTheType() {
    // Two sources of one type (Cases and Tasks), several items sharing a
    // moment: pages of 3 bring back each item once, newest first.
    Contact fresh = new Contact(LastName = 'View all');
    insert fresh;
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 7; i++) {
      cases.add(new Case(ContactId = fresh.Id, Subject = 'Case ' + i, Status = 'New', Origin = 'Web'));
    }
    insert cases;
    List<Task> tasks = new List<Task>();
    for (Integer i = 0; i < 4; i++) {
      tasks.add(new Task(WhoId = fresh.Id, Subject = 'Task ' + i));
    }
    insert tasks;
    Datetime base = Datetime.now().addDays(-2);
    for (Integer i = 0; i < 7; i++) {
      // Three cases at the same moment.
      Test.setCreatedDate(cases[i].Id, base.addMinutes(-Math.max(i, 2)));
    }
    for (Integer i = 0; i < 4; i++) {
      Test.setCreatedDate(tasks[i].Id, base.addMinutes(-2 * i));
    }
    Time_Drive_Source__mdt taskSource = source('CaseTasks', 'Task', 'CreatedDate', 'WhoId');
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId'),
      taskSource
    };

    Set<String> seen = new Set<String>();
    Datetime previous;
    String cursor;
    Integer pages = 0;
    TimeDriveController.GroupPage page;
    do {
      page = TimeDriveController.getGroupPage(fresh.Id, 'case', base.addHours(-1), base.addHours(1), 3, cursor);
      if (pages == 0) {
        Assert.areEqual('View all', page.recordName);
        Assert.isFalse(page.dateOnly);
      }
      Assert.isTrue(page.items.size() <= 3);
      for (TimeDriveController.EngagementEvent e : page.items) {
        Assert.isTrue(seen.add(e.id), 'shown twice: ' + e.id);
        Assert.isTrue(previous == null || e.occurredAt <= previous, 'newest first');
        previous = e.occurredAt;
      }
      cursor = page.cursor;
      pages++;
    } while (page.more && pages < 10);
    Assert.areEqual(11, seen.size(), 'every case and task once');
    Assert.areEqual(4, pages);
  }

  @IsTest
  static void viewAllReadsDateOnlyItemsByTheirDay() {
    // Tasks by ActivityDate plot at midday, so a counted row's span is an
    // instant: the page reads the whole day.
    Contact fresh = new Contact(LastName = 'Date only');
    insert fresh;
    List<Task> tasks = new List<Task>();
    for (Integer i = 0; i < 5; i++) {
      tasks.add(new Task(WhoId = fresh.Id, Subject = 'Task ' + i, ActivityDate = Date.today()));
    }
    insert tasks;
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('DatedTasks', 'Task', 'ActivityDate', 'WhoId')
    };
    Datetime midday = Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0));
    TimeDriveController.GroupPage page = TimeDriveController.getGroupPage(fresh.Id, 'case', midday, midday, 50, null);
    Assert.areEqual(5, page.items.size());
    Assert.isTrue(page.dateOnly);
    Assert.isFalse(page.more);
  }

  @IsTest
  static void viewAllShowsTheSourcesOwnDetailFields() {
    // The columns are the admin's detail fields, as an opened item's are.
    Contact fresh = new Contact(LastName = 'Columns');
    insert fresh;
    Case broken = new Case(ContactId = fresh.Id, Subject = 'Broken', Status = 'New', Origin = 'Web');
    insert broken;
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    TimeDriveConfig.testDetailFields = new Map<String, List<Time_Drive_Detail_Field__mdt>>{
      'Cases' => new List<Time_Drive_Detail_Field__mdt>{
        new Time_Drive_Detail_Field__mdt(Label = 'Status', Field__c = 'Status'),
        new Time_Drive_Detail_Field__mdt(Label = 'Contact', Field__c = 'Contact.Name')
      }
    };
    TimeDriveController.GroupPage page = TimeDriveController.getGroupPage(
      fresh.Id,
      'case',
      Datetime.now().addHours(-1),
      Datetime.now().addHours(1),
      50,
      null
    );
    Assert.areEqual(1, page.items.size());
    List<TimeDriveController.Detail> details = page.items[0].details;
    Assert.areEqual(2, details.size());
    Assert.areEqual('Status', details[0].label);
    Assert.areEqual('New', details[0].value);
    Assert.areEqual('Columns', details[1].value, 'the contact by name');
  }

  @IsTest
  static void groupedRowsSayWhetherTheyCanBeListed() {
    Contact fresh = new Contact(LastName = 'Pageable');
    insert fresh;
    List<Case> cases = new List<Case>();
    for (Integer i = 0; i < 55; i++) {
      cases.add(new Case(ContactId = fresh.Id, Subject = 'Case ' + i, Status = 'New', Origin = 'Web'));
    }
    insert cases;
    String day = Datetime.now().format('yyyy-MM-dd');
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      fresh.Id,
      null,
      null,
      null,
      null,
      new List<String>{ day },
      new List<String>{ day }
    );
    Assert.areEqual(1, page.size(), String.valueOf(page));
    Assert.isTrue(page[0].grouped);
    Assert.isTrue(page[0].pageable, 'Salesforce rows can be listed');

    // A Data 360 source of the same type: not listed (yet).
    Time_Drive_Source__mdt d360 = data360Sources()[0];
    d360.Event_Type__c = 'case';
    d360.Parent_Object__c = 'Contact';
    d360.Active__c = true;
    TimeDriveConfig.testSources.add(d360);
    page = TimeDriveController.getDays(
      fresh.Id,
      null,
      null,
      null,
      null,
      new List<String>{ day },
      new List<String>{ day }
    );
    for (TimeDriveController.EngagementEvent e : page) {
      if (e.grouped) {
        Assert.isFalse(e.pageable);
      }
    }
  }

  private static List<Time_Drive_Source__mdt> data360Sources() {
    List<Time_Drive_Source__mdt> sources = new List<Time_Drive_Source__mdt>();
    for (
      String name : new List<String>{
        'ssot__EmailEngagement__dlm',
        'ssot__MessageEngagement__dlm',
        'ssot__WebsiteEngagement__dlm',
        'ssot__WebSearchEngagement__dlm',
        'ssot__DeviceApplicationEngagement__dlm',
        'ssot__ShoppingCartEngagement__dlm'
      }
    ) {
      sources.add(
        new Time_Drive_Source__mdt(
          DeveloperName = name.replace('__dlm', ''),
          Label = name,
          Kind__c = 'Data 360',
          Object_Name__c = name,
          Title__c = 'Email {Action}',
          Subtitle__c = '{ssot__Name__c}',
          Event_Type__c = 'email',
          Category__c = 'Marketing'
        )
      );
    }
    return sources;
  }

  @IsTest
  static void fieldsReachedThroughLookupsAreDescribedWhereTheyLive() {
    TimeDriveConfig.PathField close = TimeDriveConfig.pathField('OpportunityContactRole', 'Opportunity.CloseDate');
    Assert.isNotNull(close, 'a lookup is followed');
    Assert.areEqual('Opportunity', close.owner);
    Assert.areEqual('Opportunity.', close.prefix);
    Assert.areEqual(Schema.DisplayType.DATE, close.field.getType());
    Assert.areEqual(
      Schema.DisplayType.DATE,
      TimeDriveConfig.fieldDescribe('OpportunityContactRole', 'Opportunity.CloseDate').getType(),
      'fieldDescribe takes a path too'
    );

    TimeDriveConfig.PathField own = TimeDriveConfig.pathField('Task', 'ActivityDate');
    Assert.areEqual('Task', own.owner);
    Assert.areEqual('', own.prefix, 'a field of the object itself');

    Assert.isNull(TimeDriveConfig.pathField('Task', 'Who.Name'), 'a polymorphic lookup is not followed');
    Assert.isNull(TimeDriveConfig.pathField('OpportunityContactRole', 'Opportunity.NoSuchField'));
    Assert.isNull(TimeDriveConfig.pathField('OpportunityContactRole', 'NoSuchLookup.CloseDate'));
    Assert.isNull(TimeDriveConfig.pathField('NoSuchObject', 'Opportunity.CloseDate'));
    Assert.isNull(TimeDriveConfig.fieldDescribe('OpportunityContactRole', 'Opportunity.NoSuchField'));
  }

  @IsTest
  static void aSourceCanBeAJunctionWithItsFieldsReachedThroughIt() {
    // OpportunityContactRole is the source (linked by ContactId); the date,
    // title and filter are the Opportunity's, by path.
    Time_Drive_Source__mdt source = source('Roles', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    source.Title__c = '{Opportunity.Name}';
    source.Filter__c = 'Opportunity.IsWon = true';
    source.Record_Id_Field__c = 'OpportunityId';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source };

    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(contactId(), null, null, '1', null);
    Assert.areEqual(1, summary.total, 'only the won opportunity is counted, by its close date');
    Assert.areEqual(1, summary.days.size());
    Assert.areEqual(String.valueOf(Date.today().addDays(-5)), summary.days[0].key);

    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      contactId(),
      null,
      null,
      '1',
      null,
      new List<String>{ summary.days[0].key },
      null
    );
    Assert.areEqual(1, page.size());
    Assert.areEqual('Holiday party', page[0].title, 'the title is read through the junction');
    Assert.areEqual(Opportunity.SObjectType, page[0].recordId.getSObjectType(), 'it opens the opportunity');
    Assert.areEqual('Opportunity', page[0].sourceObject);
  }

  @IsTest
  static void activitiesOnEveryContactAreCountedThroughTheirRelations() {
    // Needs Shared Activities, which a scratch org may not have.
    if (!Schema.getGlobalDescribe().containsKey('taskrelation')) {
      return;
    }
    Contact fresh = new Contact(LastName = 'Shared');
    insert fresh;
    Date day = Date.today().addDays(-3);
    Task kept = new Task(WhoId = fresh.Id, Subject = 'Kept', ActivityDate = day, Status = 'Completed');
    Task gone = new Task(WhoId = fresh.Id, Subject = 'Gone', ActivityDate = day, Status = 'Completed');
    insert new List<Task>{ kept, gone };
    delete gone;
    Time_Drive_Source__mdt source = source('Shared', 'TaskRelation', 'Task.ActivityDate', 'RelationId');
    source.Title__c = '{Task.Subject}';
    source.Record_Id_Field__c = 'TaskId';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source };

    TimeDriveController.TimelineSummary summary = TimeDriveController.getSummary(fresh.Id, null, null, '1', null);
    Assert.areEqual(1, summary.total, 'counted without the deleted task');
    List<TimeDriveController.EngagementEvent> page = TimeDriveController.getDays(
      fresh.Id,
      null,
      null,
      '1',
      null,
      new List<String>{ String.valueOf(day) },
      null
    );
    Assert.areEqual(1, page.size());
    Assert.areEqual('Kept', page[0].title);
    Assert.areEqual(Task.SObjectType, page[0].recordId.getSObjectType());
    Assert.areEqual('Task', page[0].sourceObject);
  }

  @IsTest
  static void aLookupsLabelLeavesOffTheIdApexAddsToIt() {
    TimeDriveRow row = new TimeDriveRow(new Task(Subject = 'Call', Status = 'Completed'));
    Assert.areEqual('Related To', row.labelOf('WhatId'), 'a lookup reads as the page names it');
    Assert.areEqual('Related To', row.labelOf('What.Name'), 'so does a path through it that ends at Name');
    Assert.areEqual('Subject', row.labelOf('Subject'), 'other fields are as they were');
    Assert.areEqual('Status', row.labelOf('Status'));
    // Only a lookup's: the record's own Id is not one, and keeps its "ID".
    Schema.DescribeFieldResult id = Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
      .fields.getMap()
      .get('id')
      .getDescribe();
    Assert.areEqual(id.getLabel(), TimeDriveRow.plainLabel(id));
  }

  @IsTest
  static void aFilesItemStandsForItsDocument() {
    Time_Drive_Source__mdt files = source('Files', 'ContentDocumentLink', 'SystemModstamp', 'LinkedEntityId');
    Assert.areEqual(
      'ContentDocumentId',
      new TimeDriveContext(null, 'Contact', null, files, null, null).recordIdField(),
      'a click opens the document, whatever the file is dated by'
    );
    files.Record_Id_Field__c = 'Id';
    Assert.areEqual(
      'Id',
      new TimeDriveContext(null, 'Contact', null, files, null, null).recordIdField(),
      'unless it says otherwise'
    );
    Assert.areEqual(
      'Id',
      new TimeDriveContext(null, 'Contact', null, source('Cases', 'Case', 'CreatedDate', 'ContactId'), null, null)
        .recordIdField(),
      'other objects are as they were'
    );
  }

  @IsTest
  static void aFilesSourceIsNamedWithItsTranslatableLabelUnlessItSaysOtherwise() {
    Time_Drive_Source__mdt s = source('Files', 'ContentDocumentLink', 'ContentDocument.CreatedDate', 'LinkedEntityId');
    Assert.areEqual(
      Label.Time_Drive_Legend_Files,
      TimeDriveConfig.legendLabel(s),
      'Files & Notes, in the viewer\'s language'
    );
    Assert.areEqual('Files & Notes', Label.Time_Drive_Legend_Files);
    s = source('Files2', 'ContentDocumentLink', 'ContentDocument.CreatedDate', 'LinkedEntityId');
    s.Event_Label__c = 'Attachments';
    Assert.areEqual('Attachments', TimeDriveConfig.legendLabel(s), 'a name of its own wins');
    s = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    Assert.areEqual(
      Case.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
      TimeDriveConfig.legendLabel(s),
      'other objects are named as before'
    );
  }

  @IsTest
  static void theLegendNameCanBeAnotherObjectsPluralName() {
    Time_Drive_Source__mdt s = source('Roles', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    s.Event_Label__c = '$Object.Opportunity';
    Assert.areEqual(
      Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
      TimeDriveConfig.legendLabel(s)
    );
    s = source('Roles2', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    s.Event_Label__c = '$Object.NoSuchObject';
    Assert.areEqual(
      'Roles2',
      TimeDriveConfig.legendLabel(s),
      'an object that is not there falls back to the source\'s name'
    );
    s = source('Roles3', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    Assert.areEqual(
      Opportunity.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
      TimeDriveConfig.legendLabel(s),
      'with no name set, a source dated by its record is named after it'
    );
  }

  @IsTest
  static void filtersAreRewrittenToReachTheirFieldsAcrossARelationship() {
    String t = 'Task';
    Assert.areEqual(
      'Task.TaskSubtype = \'Call\'',
      TimeDriveSoqlProvider.prefixed('TaskSubtype = \'Call\'', t, 'Task.')
    );
    Assert.areEqual(
      '(Task.TaskSubtype = null OR Task.TaskSubtype NOT IN (\'Call\', \'Email\'))',
      TimeDriveSoqlProvider.prefixed('(TaskSubtype = null OR TaskSubtype NOT IN (\'Call\', \'Email\'))', t, 'Task.')
    );
    Assert.areEqual(
      'Task.Status = \'Subject = x\' AND Task.Priority = :priority',
      TimeDriveSoqlProvider.prefixed('Status = \'Subject = x\' AND Priority = :priority', t, 'Task.'),
      'text in quotes and binds are left alone'
    );
    Assert.areEqual(
      'Task.ActivityDate >= LAST_N_DAYS:30 AND Task.ActivityDate < TODAY AND Task.CreatedDate > 2026-01-31T10:00:00Z',
      TimeDriveSoqlProvider.prefixed(
        'ActivityDate >= LAST_N_DAYS:30 AND ActivityDate < TODAY AND CreatedDate > 2026-01-31T10:00:00Z',
        t,
        'Task.'
      ),
      'date literals are left alone'
    );
    Assert.areEqual(
      'DAY_ONLY(Task.CreatedDate) = TODAY',
      TimeDriveSoqlProvider.prefixed('DAY_ONLY(CreatedDate) = TODAY', t, 'Task.'),
      'a function stays, its field is prefixed'
    );
    Assert.areEqual(
      'Task.CreatedBy.Name = \'A\'',
      TimeDriveSoqlProvider.prefixed('CreatedBy.Name = \'A\'', t, 'Task.'),
      'a path is prefixed whole'
    );
    Assert.isNull(
      TimeDriveSoqlProvider.prefixed('Id IN (SELECT TaskId FROM TaskRelation)', t, 'Task.'),
      'a subquery is not rewritten'
    );
    Assert.isNull(
      TimeDriveSoqlProvider.prefixed('NoSuchField__c = 1', t, 'Task.'),
      'an unknown word is not guessed at'
    );
    Assert.isNull(TimeDriveSoqlProvider.prefixed('Subject = \'open', t, 'Task.'), 'an unclosed quote is not rewritten');
  }

  @IsTest
  static void aJunctionSourceCountsThroughTheJunctionAndGivesTheSameAnswer() {
    // OpportunityContactRole links Opportunities to the Contact, as Setup
    // saves it: the Opportunity is the source, the role the junction.
    Contact c = [SELECT Id FROM Contact LIMIT 1];
    Time_Drive_Source__mdt source = source('Opps', 'Opportunity', 'CloseDate', null);
    source.Parent_Field__c = null;
    source.Junction_Object__c = 'OpportunityContactRole';
    source.Junction_Parent_Field__c = 'ContactId';
    source.Junction_Record_Field__c = 'OpportunityId';
    source.Title__c = '{Name}';
    source.Filter__c = 'IsWon = true';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ source };

    TimeDriveDiagnostics.begin();
    Datetime since = Datetime.now().addYears(-1);
    TimeDriveContext context = new TimeDriveContext(c.Id, null, since, source, null, null);
    TimeDriveSoqlProvider provider = new TimeDriveSoqlProvider();
    List<TimeDriveContext.DayCount> counts = provider.countDays(context, TimeDriveContext.UNIT_DAY);
    Integer total = 0;
    for (TimeDriveContext.DayCount d : counts) {
      total += d.count;
    }
    Assert.areEqual(1, total, 'the won opportunity, counted from the role');
    String counted;
    for (TimeDriveDiagnostics.Query q : TimeDriveDiagnostics.queries) {
      if (q.kind == 'count') {
        counted = q.soql;
      }
    }
    Assert.isNotNull(counted, 'the count was recorded');
    Assert.isTrue(counted.contains('FROM OpportunityContactRole'), 'counted from the junction: ' + counted);
    Assert.isTrue(counted.contains('Opportunity.CloseDate'), 'the date is read across the role: ' + counted);
    Assert.isTrue(counted.contains('Opportunity.IsWon = true'), 'so is the filter: ' + counted);

    // A filter that can't be rewritten is counted the usual way, with the same answer.
    source.Filter__c = 'Id IN (SELECT OpportunityId FROM OpportunityContactRole WHERE IsPrimary = false)';
    TimeDriveDiagnostics.begin();
    counts = provider.countDays(new TimeDriveContext(c.Id, null, since, source, null, null), TimeDriveContext.UNIT_DAY);
    for (TimeDriveDiagnostics.Query q : TimeDriveDiagnostics.queries) {
      if (q.kind == 'count') {
        counted = q.soql;
      }
    }
    Assert.isTrue(
      counted.contains('FROM Opportunity '),
      'a subquery in the filter keeps the original form: ' + counted
    );
  }

  private static Time_Drive_Source__mdt source(String name, String objectName, String dateField, String parentField) {
    return new Time_Drive_Source__mdt(
      DeveloperName = name,
      Label = name,
      Active__c = true,
      Sequence__c = 1,
      Parent_Object__c = 'Contact',
      Object_Name__c = objectName,
      Date_Field__c = dateField,
      Parent_Field__c = parentField,
      Event_Type__c = 'case',
      Category__c = 'Service',
      Title__c = 'Case'
    );
  }
}
