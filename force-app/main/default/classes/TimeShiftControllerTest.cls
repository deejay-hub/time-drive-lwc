@IsTest
private class TimeShiftControllerTest {
  // The sources the timeline once shipped with, in place of the org's.
  static {
    TimeShiftTestData.useShipped();
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

  private static Integer countOf(TimeShiftController.TimelineResult result, String type) {
    Integer n = 0;
    for (TimeShiftController.EngagementEvent e : result.events) {
      if (e.type == type) {
        n++;
      }
    }
    return n;
  }

  @IsTest
  static void everySourcesEventsMergeNewestFirst() {
    Test.startTest();
    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(
      contactId()
    );
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
    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(
      contactId()
    );
    Assert.areEqual(2, countOf(result, 'opportunity'), 'both opportunities opened in the window');
    Assert.areEqual(1, countOf(result, 'opportunity_won'));
    Assert.areEqual(0, countOf(result, 'opportunity_lost'));
    for (TimeShiftController.EngagementEvent e : result.events) {
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
    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      customer,
      null,
      null,
      null,
      null
    );
    Integer counted = 0;
    Integer orders = 0;
    for (TimeShiftController.DaySummary day : summary.days) {
      counted += day.count;
      orders += day.orders;
    }
    Assert.areEqual(summary.total, counted, 'every event is in a day');
    Assert.areEqual(summary.unfilteredTotal, summary.total, 'no filters');
    Assert.areEqual(2, orders, 'both orders');
    Assert.isFalse(summary.types.isEmpty());
    Assert.isFalse(summary.noSources, 'the Contact page has sources');
    Assert.areEqual(Contact.SObjectType.getDescribe().getLabel(), summary.page);
    // Every source in the view is offered to the filters, items or not.
    Set<String> offered = new Set<String>();
    for (TimeShiftController.TypeCount t : summary.types) {
      offered.add(t.type);
    }
    for (Time_Shift_Source__mdt s : TimeShiftConfig.allSources().values()) {
      if (s.Active__c == true && String.isNotBlank(s.Event_Type__c) && s.Parent_Object__c == 'Contact') {
        Assert.isTrue(offered.contains(s.Event_Type__c), s.Event_Type__c + ' is offered');
      }
    }
  }

  @IsTest
  static void countedSourcesArentCappedByMaxRecords() {
    Id customer = contactId();
    insert new Case(ContactId = customer, Subject = 'Wrong item', Status = 'New', Origin = 'Web');
    Time_Shift_Source__mdt cases = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    cases.Max_Records__c = 1;
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ cases };

    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      customer,
      null,
      null,
      null,
      null
    );
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };

    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      customer,
      null,
      null,
      null,
      null
    );
    String today = Datetime.now().format('yyyy-MM-dd');
    String quiet = threeDaysAgo.format('yyyy-MM-dd');
    Assert.areEqual(2, summary.days.size());
    Assert.areEqual(today, summary.days[0].key);
    Assert.areEqual(61, summary.days[0].count, 'the 60 and the setup case');

    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today, quiet },
      null
    );
    Assert.areEqual(2, page.size(), 'the busy day grouped, the quiet day in full');
    TimeShiftController.EngagementEvent grouped = page[0];
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    String today = Datetime.now().format('yyyy-MM-dd');
    String quiet = threeDaysAgo.format('yyyy-MM-dd');

    // A quiet page: no count at all, just the rows (one query).
    Integer before = Limits.getQueries();
    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
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
    page = TimeShiftController.getDays(
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
    page = TimeShiftController.getDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today },
      new List<String>()
    );
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    String today = Datetime.now().format('yyyy-MM-dd');
    String quiet = threeDaysAgo.format('yyyy-MM-dd');

    // The summary says which sources it counted, and what each period holds
    // of them (the counts only for a busy period).
    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(customer, null, null, null, null);
    Assert.areEqual(new List<String>{ 'Cases' }, summary.counted);
    for (TimeShiftController.DaySummary d : summary.days) {
      Assert.areEqual(new List<Integer>{ 0 }, d.src);
      if (d.key == today) {
        Assert.areEqual(new List<Integer>{ 61 }, d.n);
      } else {
        Assert.isNull(d.n, 'a quiet period keeps no counts');
      }
    }

    // A busy period's grouped row from the summary's count: no count query,
    // and it stands for the whole day.
    TimeShiftController.BusyCount known = new TimeShiftController.BusyCount();
    known.key = today;
    known.source = 'Cases';
    known.count = 61;
    Integer before = Limits.getQueries();
    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getPageDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today },
      new List<String>{ today },
      new List<String>(),
      new List<TimeShiftController.BusyCount>{ known },
      null
    );
    Assert.areEqual(1, page.size());
    Assert.isTrue(page[0].grouped);
    Assert.isTrue(page[0].allDay, 'a count for the day says no hour');
    Assert.areEqual(61, page[0].groupCount);
    Integer withHint = Limits.getQueries() - before;
    before = Limits.getQueries();
    TimeShiftController.getDays(
      customer,
      null,
      null,
      null,
      null,
      new List<String>{ today },
      new List<String>{ today }
    );
    Assert.isTrue(withHint < Limits.getQueries() - before, 'the hint saves the count');

    // A source the summary found nothing in is not asked.
    before = Limits.getQueries();
    page = TimeShiftController.getPageDays(
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Tasks', 'Task', 'ActivityDate', 'WhoId'),
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    TimeShiftDiagnostics.begin();
    TimeShiftController.getTimeline(customer, null, null, null, null, null, null, null, null);
    TimeShiftDiagnostics.finish();
    Boolean sawTask = false;
    for (TimeShiftDiagnostics.Query q : TimeShiftDiagnostics.queries) {
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
    Integer[] daysBack = new Integer[]{ 1, 3, 4, 8, 9, 20 };
    for (Integer i = 0; i < cases.size(); i++) {
      Datetime at = Datetime.now().addDays(-daysBack[i]);
      Test.setCreatedDate(cases[i].Id, at);
      keys.add(at.format('yyyy-MM-dd'));
    }
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    // The first five follow one another in the summary: one run. The sixth
    // is not asked with them.
    List<String> run = new List<String>{ keys[4], keys[3], keys[2], keys[1], keys[0] };
    String together = String.join(run, ',');

    TimeShiftDiagnostics.begin();
    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getPageDays(
      customer, null, null, null, null, run, new List<String>(), null, null, new List<String>{ together }
    );
    TimeShiftDiagnostics.finish();
    Assert.areEqual(5, page.size());
    Integer rangesAsRun = TimeShiftDiagnostics.queries[0].soql.split('CreatedDate >= ').size() - 1;
    Assert.areEqual(1, rangesAsRun, 'one range for the run');

    // Without the runs: a range for each day, the same rows.
    TimeShiftDiagnostics.begin();
    List<TimeShiftController.EngagementEvent> apart = TimeShiftController.getPageDays(
      customer, null, null, null, null, run, new List<String>(), null, null, null
    );
    TimeShiftDiagnostics.finish();
    Assert.areEqual(5, apart.size());
    Assert.areEqual(5, TimeShiftDiagnostics.queries[0].soql.split('CreatedDate >= ').size() - 1, 'a range for each');
    Set<Id> ids = new Set<Id>();
    for (TimeShiftController.EngagementEvent e : page) {
      ids.add(e.recordId);
    }
    for (TimeShiftController.EngagementEvent e : apart) {
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
    Time_Shift_Source__mdt source = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    source.Max_Records__c = 5;
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source };

    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
      fresh.Id,
      null,
      null,
      null,
      null,
      keys,
      new List<String>()
    );
    Assert.areEqual(12, page.size(), 'every item, though each read stops at 5');
    for (TimeShiftController.EngagementEvent e : page) {
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
    page = TimeShiftController.getDays(
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
    Assert.areEqual(2000, TimeShiftData360Provider.MAX_DMO_ROWS);
  }

  @IsTest
  static void identityLinksAreKeptBetweenRequests() {
    TimeShiftCache.testStore = new Map<String, Object>();
    Id customer = contactId();
    String key = TimeShiftCache.key(new List<String>{ 'ids', customer, null });
    TimeShiftCache.put(key, new Set<String>{ 'UNIFIED-1', 'WEB-9' });
    List<String> warnings = new List<String>();
    TimeShiftContext context = new TimeShiftContext(
      customer,
      'Contact',
      Datetime.now(),
      null,
      null,
      warnings
    );
    // Kept from an earlier request: no link object needed, no warning.
    Set<String> ids = TimeShiftData360Provider.individualIdsFor(
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
    TimeShiftCache.testStore = null;
    TimeShiftCache.put('x', 'y');
    Assert.isNull(TimeShiftCache.get('nothingKept'));
  }

  @IsTest
  static void countsAreBatchedUnderTheGroupLimit() {
    Datetime since = Datetime.newInstance(Date.newInstance(2026, 1, 1), Time.newInstance(9, 0, 0, 0));
    Datetime until = Datetime.newInstance(Date.newInstance(2026, 1, 10), Time.newInstance(17, 0, 0, 0));
    List<List<TimeShiftController.TimeWindow>> batches = TimeShiftSoqlProvider.batches(
      new List<TimeShiftController.TimeWindow>{
        new TimeShiftController.TimeWindow(since, until)
      },
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
    Assert.areEqual('2026-01-08', TimeShiftContext.periodKey(Date.newInstance(2026, 1, 9), 'week'));
    Assert.areEqual('2026-12-31', TimeShiftContext.periodKey(Date.newInstance(2026, 12, 31), 'week'));
    Assert.areEqual(
      Date.newInstance(2026, 12, 30),
      TimeShiftContext.periodEnd(Date.newInstance(2026, 12, 24), 'week')
    );
    Assert.areEqual(
      Date.newInstance(2026, 12, 31),
      TimeShiftContext.periodEnd(Date.newInstance(2026, 12, 31), 'week')
    );
    Assert.areEqual('2026-02-01', TimeShiftContext.periodKey(Date.newInstance(2026, 2, 17), 'month'));
    Assert.areEqual(
      Date.newInstance(2026, 2, 28),
      TimeShiftContext.periodEnd(Date.newInstance(2026, 2, 1), 'month')
    );
    Assert.areEqual('2026-02-17', TimeShiftContext.periodKey(Date.newInstance(2026, 2, 17), 'day'));
  }

  @IsTest
  static void longWindowsWithManySourcesCountByWeek() {
    Id customer = contactId();
    List<Time_Shift_Source__mdt> many = new List<Time_Shift_Source__mdt>();
    for (Integer i = 0; i < 5; i++) {
      many.add(source('Cases_' + i, 'Case', 'CreatedDate', 'ContactId'));
    }
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ many[0] };
    // Ten years back and ahead: one source still fits by day...
    Assert.areEqual('day', TimeShiftController.getSummary(customer, null, null, '10', '10').unit);

    // ...five don't (5 x 7,305 days > COUNT_ROWS), so they count by week.
    TimeShiftConfig.testSources = many;
    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      customer,
      null,
      null,
      '10',
      '10'
    );
    String week = TimeShiftContext.periodKey(Date.today(), 'week');
    Assert.areEqual('week', summary.unit);
    Assert.areEqual(1, summary.days.size());
    Assert.areEqual(week, summary.days[0].key, 'keyed by the week\'s first day');
    Assert.areEqual(5, summary.days[0].count, 'the case, once per source');

    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
      customer,
      null,
      null,
      '10',
      '10',
      new List<String>{ week },
      null
    );
    Assert.areEqual(5, page.size());
    for (TimeShiftController.EngagementEvent e : page) {
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
    Time_Shift_Source__mdt source = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    source.Max_Records__c = 5;
    source.Title__c = '{Subject}';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source };

    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
      customer,
      null,
      null,
      '1',
      null,
      new List<String>{ String.valueOf(older), String.valueOf(newer) },
      null
    );
    Set<String> titles = new Set<String>();
    for (TimeShiftController.EngagementEvent e : page) {
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
    Time_Shift_Source__mdt source = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    source.Title__c = '{Subject}';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source };

    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      customer,
      null,
      null,
      '1',
      null
    );
    Assert.areEqual(1, summary.total, 'counted without the deleted one');
    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
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
    Assert.isTrue(TimeShiftSoqlProvider.ARCHIVED_OBJECTS.contains('Task'));
  }

  @IsTest
  static void aSourceTheFiltersHideIsNotCounted() {
    Id customer = contactId();
    insert new Task(WhoId = customer, Subject = 'A', ActivityDate = Date.today(), Status = 'Completed');
    Time_Shift_Source__mdt tasks = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    tasks.Event_Type__c = 'task';
    Time_Shift_Source__mdt cases = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ tasks, cases };

    Integer before = Limits.getQueries();
    TimeShiftController.TimelineSummary shown = TimeShiftController.getSummary(customer, null, null, '1', 'None');
    Integer allQueries = Limits.getQueries() - before;
    Assert.isTrue(shown.total > 0, 'the Tasks are counted');

    before = Limits.getQueries();
    TimeShiftController.TimelineSummary hidden = TimeShiftController.getSummary(
      customer,
      null,
      new List<String>{ 'task' },
      '1',
      'None'
    );
    Integer hiddenQueries = Limits.getQueries() - before;
    Assert.isTrue(hiddenQueries < allQueries, 'the hidden Tasks source was not counted: ' + hiddenQueries + ' v ' + allQueries);
    Assert.isTrue(hidden.total < shown.total, 'without the Tasks: ' + hidden.total + ' v ' + shown.total);
    Assert.areEqual(hidden.total, hidden.unfilteredTotal, 'only what is counted');
    // Its type is still offered in the panel, so it can be turned back on.
    Set<String> offered = new Set<String>();
    for (TimeShiftController.TypeCount t : hidden.types) {
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
    List<Time_Shift_Source__mdt> many = new List<Time_Shift_Source__mdt>();
    for (Integer i = 0; i < 5; i++) {
      Time_Shift_Source__mdt birthdays = source('Birthdays_' + i, 'Contact', 'Birthdate', 'Id');
      birthdays.Max_Records__c = 1;
      many.add(birthdays);
    }
    TimeShiftConfig.testSources = many;
    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(customer, null, null, '10', '10');
    Assert.areEqual('week', summary.unit);
    Assert.isTrue(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
    Assert.areEqual(1, summary.days.size(), 'one week has the date');
    Assert.areEqual(TimeShiftContext.periodKey(day, 'week'), summary.days[0].key);
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
    List<Time_Shift_Source__mdt> many = new List<Time_Shift_Source__mdt>();
    for (Integer i = 0; i < 5; i++) {
      Time_Shift_Source__mdt tasks = source('Tasks_' + i, 'Task', 'ActivityDate', 'WhoId');
      tasks.Max_Records__c = 1;
      many.add(tasks);
    }
    TimeShiftConfig.testSources = many;
    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      customer,
      null,
      null,
      '10',
      '10'
    );
    Assert.areEqual('week', summary.unit);
    Assert.isTrue(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
    Map<String, Integer> byWeek = new Map<String, Integer>();
    for (TimeShiftController.DaySummary d : summary.days) {
      byWeek.put(d.key, d.count);
    }
    Assert.areEqual(10, byWeek.get(TimeShiftContext.periodKey(today, 'week')), 'two tasks, five sources');
    Assert.areEqual(5, byWeek.get(TimeShiftContext.periodKey(today.addDays(-400), 'week')));
  }

  @IsTest
  static void data360CountsRunInDataSpaceSql() {
    Map<String, Schema.SObjectType> objects = new Map<String, Schema.SObjectType>{
      'ssot__individual__dlm' => Contact.SObjectType,
      'ssot__emailengagement__dlm' => Contact.SObjectType
    };
    Time_Shift_Source__mdt email = data360Sources()[0];
    email.Data_Space__c = 'timeshift';
    StubSql stub = new StubSql(
      new List<List<Object>>{ new List<Object>{ '2026-10-12', 14, 3 }, new List<Object>{ '2026-10-13', 9, 1200 } }
    );
    TimeShiftData360Provider.sqlRunner = stub;
    TimeShiftContext context = new TimeShiftContext(
      contactId(),
      'Contact',
      Datetime.now().addDays(-30),
      email,
      null,
      new List<String>()
    );
    context.until = Datetime.now();

    List<TimeShiftContext.DayCount> counts = new TimeShiftData360Provider()
      .countDays(context, 'hour', objects);
    Assert.areEqual(2, counts.size());
    Assert.areEqual('2026-10-13', counts[1].dayKey);
    Assert.areEqual(9, counts[1].hour);
    Assert.areEqual(1200, counts[1].count);
    Assert.areEqual('timeshift', stub.dataSpace);
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
    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(
      contactId(),
      null,
      null,
      null,
      null
    );
    Assert.isTrue(summary.total > 0, 'CRM events still count');
    if (!Schema.getGlobalDescribe().containsKey('ssot__individual__dlm')) {
      Assert.isFalse(summary.warnings.isEmpty(), String.join(summary.warnings, ' | '));
    }
  }

  private class StubSql implements TimeShiftData360Provider.SqlRunner {
    List<List<Object>> rows;
    String sql;
    String dataSpace;

    StubSql(List<List<Object>> rows) {
      this.rows = rows;
    }

    public List<List<Object>> run(String sql, String dataSpace) {
      this.sql = sql;
      this.dataSpace = dataSpace;
      return rows;
    }
  }

  private static TimeShiftController.EngagementEvent event(
    String id,
    String type,
    String day,
    Datetime at
  ) {
    TimeShiftController.EngagementEvent e = new TimeShiftController.EngagementEvent(
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
    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(
      contactId()
    );
    Assert.areEqual(2, countOf(result, 'purchase'), 'Salesforce sources still load');
    Assert.areEqual(0, countOf(result, 'email'), 'no Data 360 engagement here');
    if (!Schema.getGlobalDescribe().containsKey('ssot__individual__dlm')) {
      Assert.isFalse(result.warnings.isEmpty(), 'explains that Data 360 is missing');
    }
  }

  @IsTest
  static void noContactGivesAnEmptyTimeline() {
    Assert.isTrue(TimeShiftController.getEvents(null).events.isEmpty());
  }

  @IsTest
  static void data360ActionsReadNaturally() {
    Assert.areEqual('opened', TimeShiftData360Provider.actionText('Open'));
    Assert.areEqual('page view', TimeShiftData360Provider.actionText('Page View'));
    Assert.areEqual('Bounce', TimeShiftData360Provider.actionText('Bounce'));
    Assert.isNull(TimeShiftData360Provider.actionText(null));
  }

  @IsTest
  static void identityLinksFallBackToTheContactsOwnIndividual() {
    Id customer = contactId();
    List<String> warnings = new List<String>();
    TimeShiftData360Provider.testSetting = new Time_Shift_Setting__mdt(
      Identity_Link_Object__c = 'UnifiedLinkssotIndividualTimeShift__dlm'
    );
    Set<String> ids = TimeShiftData360Provider.individualIdsFor(
      customer,
      new Map<String, Schema.SObjectType>(),
      new TimeShiftContext(customer, 'Contact', Datetime.now(), null, null, warnings)
    );
    Assert.isTrue(ids.contains(String.valueOf(customer)));
    Assert.areEqual(1, warnings.size());
    Assert.isTrue(warnings[0].contains('UnifiedLinkssotIndividualTimeShift__dlm'), 'names the configured link object');
  }

  @IsTest
  static void identityLinksAreFoundByTheirRulesetsName() {
    // The link DMO set isn't there; identity resolution's ruleset one is.
    TimeShiftData360Provider.testDmoNames = new List<String>{
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
      TimeShiftData360Provider.linkObjectIn(objects, 'IndividualIdentityLink__dlm', 'default')
    );
    // The one set wins when it's there.
    objects.put('individualidentitylink__dlm', Contact.SObjectType);
    Assert.areEqual(
      'IndividualIdentityLink__dlm',
      TimeShiftData360Provider.linkObjectIn(objects, 'IndividualIdentityLink__dlm', 'default')
    );
    TimeShiftData360Provider.testDmoNames = new List<String>();
    Assert.isNull(
      TimeShiftData360Provider.linkObjectIn(new Map<String, Schema.SObjectType>(), 'Nope__dlm', null)
    );
  }

  @IsTest
  static void customDataModelObjectsUseTheirOwnIdAndDates() {
    Id customer = contactId();
    TimeShiftContext context = new TimeShiftContext(
      customer,
      'Contact',
      Datetime.now(),
      null,
      null,
      new List<String>()
    );
    context.source = new Time_Shift_Source__mdt(Kind__c = 'Data 360', Object_Name__c = 'Reservation__dlm');
    // No ssot__Id__c on the object: its Id keys the rows.
    Map<String, Schema.SObjectField> fields = Contact.SObjectType.getDescribe().fields.getMap();
    Assert.areEqual('Id', TimeShiftData360Provider.fitIdField(context, fields).Id_Field__c);
    Assert.areEqual('Id', context.idField());
    // An Id Field that's set is kept.
    context.source = new Time_Shift_Source__mdt(Kind__c = 'Data 360', Id_Field__c = 'Reservation_ID__c');
    Assert.areEqual('Reservation_ID__c', TimeShiftData360Provider.fitIdField(context, fields).Id_Field__c);

    // A Date field is compared with days; a Date/Time one with instants.
    Assert.isTrue(TimeShiftData360Provider.isDate(fields, 'Birthdate'));
    Assert.isFalse(TimeShiftData360Provider.isDate(fields, 'CreatedDate'));
    Datetime at = Datetime.newInstance(2026, 3, 4, 10, 0, 0);
    Assert.areEqual('DATE \'2026-03-04\'', TimeShiftData360Provider.bound(at, true));
    Assert.isTrue(TimeShiftData360Provider.bound(at, false).startsWith('TIMESTAMP '));
  }

  @IsTest
  static void data360RowsAreReadForTheSpansAskedOnly() {
    // A page's quiet days, not the whole window: Max Records can't cut off
    // days further back.
    Datetime a = Datetime.newInstance(2026, 1, 5, 0, 0, 0);
    Datetime b = Datetime.newInstance(2026, 1, 5, 23, 59, 59);
    Datetime c = Datetime.newInstance(2026, 3, 9, 0, 0, 0);
    List<TimeShiftController.TimeWindow> spans = new List<TimeShiftController.TimeWindow>{
      new TimeShiftController.TimeWindow(a, b),
      new TimeShiftController.TimeWindow(c, null)
    };
    Map<String, Object> binds = new Map<String, Object>();
    Assert.areEqual(
      '(Check_in_Date__c >= :since0 AND Check_in_Date__c <= :until0) OR (Check_in_Date__c >= :since1)',
      TimeShiftData360Provider.within('Check_in_Date__c', spans, true, binds)
    );
    Assert.areEqual(Date.newInstance(2026, 1, 5), binds.get('since0'), 'a Date field gets days');
    Assert.areEqual(Date.newInstance(2026, 1, 5), binds.get('until0'));
    Assert.areEqual(Date.newInstance(2026, 3, 9), binds.get('since1'));
    Assert.isFalse(binds.containsKey('until1'));

    binds.clear();
    TimeShiftData360Provider.within('ssot__EngagementDateTm__c', spans, false, binds);
    Assert.areEqual(a, binds.get('since0'), 'a Date/Time field gets instants');
  }

  @IsTest
  static void anAccountsData360RecordsMatchItsId() {
    Account acme = new Account(Name = 'Acme');
    insert acme;
    List<String> warnings = new List<String>();
    Set<String> ids = TimeShiftData360Provider.individualIdsFor(
      acme.Id,
      new Map<String, Schema.SObjectType>(),
      new TimeShiftContext(acme.Id, 'Account', Datetime.now(), null, null, warnings)
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
    List<Time_Shift_Source__mdt> dmos = data360Sources();
    for (Time_Shift_Source__mdt s : dmos) {
      objects.put(s.Object_Name__c.toLowerCase(), Contact.SObjectType);
    }
    List<String> warnings = new List<String>();
    List<TimeShiftController.Problem> problems = new List<TimeShiftController.Problem>();
    TimeShiftData360Provider provider = new TimeShiftData360Provider();
    for (Time_Shift_Source__mdt s : dmos) {
      TimeShiftContext context = new TimeShiftContext(
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
    for (TimeShiftController.Problem p : problems) {
      Assert.areEqual('access', p.kind, p.source + ' reads fields this org lacks');
    }
  }

  @IsTest
  static void data360ObjectsMissingFromTheModelAreNamed() {
    List<String> warnings = new List<String>();
    TimeShiftData360Provider provider = new TimeShiftData360Provider();
    for (Time_Shift_Source__mdt s : data360Sources()) {
      provider.getRows(
        new TimeShiftContext(contactId(), 'Contact', Datetime.now(), s, null, warnings),
        new Map<String, Schema.SObjectType>{ 'ssot__individual__dlm' => Contact.SObjectType }
      );
    }
    Assert.areEqual(6, warnings.size(), String.join(warnings, ' | '));
    Assert.isTrue(warnings[0].contains('ssot__EmailEngagement__dlm'));

    // Without Data 360 at all, one warning however many sources ask.
    warnings.clear();
    for (Time_Shift_Source__mdt s : data360Sources()) {
      provider.getRows(
        new TimeShiftContext(contactId(), 'Contact', Datetime.now(), s, null, warnings),
        new Map<String, Schema.SObjectType>()
      );
    }
    Assert.areEqual(1, warnings.size());
  }

  @IsTest
  static void data360SourcesDefaultTheirFieldsAndProvider() {
    Time_Shift_Source__mdt s = data360Sources()[0];
    TimeShiftContext context = new TimeShiftContext(contactId(), 'Contact', Datetime.now(), s, null, null);
    Assert.areEqual('ssot__EngagementDateTm__c', context.dateField());
    Assert.areEqual('ssot__Id__c', context.idField());
    Assert.isNull(context.recordIdField());
    Assert.isTrue(TimeShiftConfig.providerFor(s, new List<String>()) instanceof TimeShiftData360Provider);
  }

  @IsTest
  static void offersTheRecordsActivityActions() {
    List<TimeShiftController.ActivityAction> actions = TimeShiftController.getActivityActions(
      contactId()
    );
    // Whatever the layout offers, each opens by API name and has an icon.
    for (TimeShiftController.ActivityAction a : actions) {
      Assert.isNotNull(a.apiName);
      Assert.isTrue(a.icon.contains(':'), a.icon);
    }
    Assert.isTrue(TimeShiftController.getActivityActions(null).isEmpty());
    Assert.areEqual(
      'action:new_task',
      TimeShiftController.iconName('https://x.my.salesforce.com/img/icon/t4v35/action/new_task_120.png')
    );
    Assert.areEqual(
      'action:log_a_call',
      TimeShiftController.iconName('https://x.my.salesforce.com/img/icon/t4v35/action/log_a_call')
    );
    Assert.areEqual('utility:add', TimeShiftController.iconName(null));
  }

  @IsTest
  static void templatesFillTokensAndDropBlankParts() {
    Opportunity o = [
      SELECT Id, Amount, Account.Name, Description
      FROM Opportunity
      WHERE StageName = 'Closed Won'
      LIMIT 1
    ];
    TimeShiftRow row = new TimeShiftRow(o);
    Assert.areEqual(
      'Ada Catering Co · ' + TimeShiftPlotter.format(3500, null, row, 'Amount'),
      TimeShiftPlotter.fill('{Account.Name} · {Amount}', row)
    );
    // No description: its part drops out.
    Assert.areEqual('Ada Catering Co', TimeShiftPlotter.fill('{Account.Name} · {Description}', row));
    Assert.areEqual(
      new Set<String>{ 'Subject', 'Account.Name' },
      TimeShiftPlotter.tokens('{Subject} at {Account.Name}')
    );
    Assert.isNull(TimeShiftPlotter.fill(null, row));
    // A title whose fields are all blank shows their labels instead.
    String descriptionLabel = Opportunity.Description.getDescribe().getLabel();
    Assert.areEqual('[' + descriptionLabel + ']', TimeShiftPlotter.title('{Description}', row));
    Assert.areEqual('Ada Catering Co', TimeShiftPlotter.title('{Account.Name} · {Description}', row));

    // Map rows from Apex providers fill the same way, keys in any case.
    TimeShiftRow mapRow = new TimeShiftRow(new Map<String, Object>{ 'Points' => 120, 'Tier' => null });
    Assert.areEqual('Earned 120 points', TimeShiftPlotter.fill('Earned {points} points · {Tier}', mapRow));
    Assert.areEqual('$12.50', TimeShiftPlotter.format(12.5, 'Currency', mapRow, 'Points'));
    Assert.areEqual(
      Date.newInstance(2026, 3, 4).format(),
      TimeShiftPlotter.format(Datetime.newInstance(2026, 3, 4, 9, 0, 0), 'Date', mapRow, 'x')
    );
    Assert.areEqual('Yes', TimeShiftPlotter.format(true, null, mapRow, 'x'));

    // Numbers lose floating-point noise and trailing zeros.
    Assert.areEqual('2713.31', TimeShiftPlotter.format(2713.3099999999999, null, mapRow, 'x'));
    Assert.areEqual('2713.31', TimeShiftPlotter.format(Double.valueOf('2713.31'), null, mapRow, 'x'));
    Assert.areEqual('2', TimeShiftPlotter.format(2.000000, null, mapRow, 'x'));
    Assert.areEqual('1500', TimeShiftPlotter.format(1500, null, mapRow, 'x'));
    // A field's own decimal places win: Probability has none.
    Opportunity deal = new Opportunity(Probability = 33.3333);
    Assert.areEqual('33', TimeShiftPlotter.format(33.3333, null, new TimeShiftRow(deal), 'Probability'));
  }

  @IsTest
  static void apexSourcesArePlottedFromTheirRecord() {
    Time_Shift_Source__mdt loyalty = new Time_Shift_Source__mdt(
      DeveloperName = 'Loyalty',
      Label = 'Loyalty',
      Active__c = true,
      Sequence__c = 50,
      Parent_Object__c = 'Contact',
      Kind__c = 'Apex',
      Provider_Class__c = 'TimeShiftExampleProvider',
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
    Time_Shift_Source__mdt orders = TimeShiftTestData.source('Order_Placed');
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ orders, loyalty };
    TimeShiftConfig.testDetailFields = new Map<String, List<Time_Shift_Detail_Field__mdt>>{
      'Loyalty' => new List<Time_Shift_Detail_Field__mdt>{
        new Time_Shift_Detail_Field__mdt(Label = 'Points', Field__c = 'Points', Format__c = 'Number'),
        new Time_Shift_Detail_Field__mdt(Label = null, Field__c = 'Balance')
      }
    };

    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(
      contactId()
    );
    List<TimeShiftController.EngagementEvent> points = new List<TimeShiftController.EngagementEvent>();
    for (TimeShiftController.EngagementEvent e : result.events) {
      if (e.type == 'loyalty') {
        points.add(e);
      }
    }
    Assert.areEqual(countOf(result, 'purchase'), points.size(), 'one loyalty event per order');
    TimeShiftController.EngagementEvent latest = points[0];
    Assert.isTrue(latest.title.startsWith('Earned '), latest.title);
    Assert.areEqual('utility:reward', latest.icon);
    Assert.areEqual('Loyalty points', latest.typeLabel);
    Assert.isNotNull(latest.recordId, 'links to the order through Record Id Field');
    Assert.isFalse(latest.useCompactLayout, 'detail fields replace the compact layout');
    Assert.areEqual('Points', latest.details[0].label);
    Assert.areEqual('Balance', latest.details[1].label, 'blank labels fall back to the field name');
    Assert.isTrue(result.warnings.isEmpty(), String.join(result.warnings, ' | '));
  }

  @IsTest
  static void theLegendNameIsTranslatedTypedOrTheObjects() {
    Time_Shift_Source__mdt s = source('Follow_Ups', 'Task', 'ActivityDate', 'WhoId');
    s.Kind__c = 'Salesforce';
    // Blank: the object's plural name, which Salesforce translates.
    Assert.areEqual(Task.SObjectType.getDescribe().getLabelPlural(), TimeShiftConfig.legendLabel(s));
    // A custom label: its value in the viewer's language.
    s.Event_Label__c = '$Label.Time_Shift_Example_Legend';
    Assert.areEqual(System.Label.get('', 'Time_Shift_Example_Legend'), TimeShiftConfig.legendLabel(s));
    Assert.areEqual('Follow-ups', TimeShiftConfig.customLabel('Time_Shift_Example_Legend'));
    // Words: as typed. A label that doesn't exist: the source's own name.
    s.Event_Label__c = 'Follow-ups';
    Assert.areEqual('Follow-ups', TimeShiftConfig.legendLabel(s));
    s.Event_Label__c = '$Label.No_Such_Label_Here';
    Assert.areEqual('Follow_Ups', TimeShiftConfig.legendLabel(s));
    Assert.isNull(TimeShiftConfig.customLabel('No_Such_Label_Here'));
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
    Time_Shift_Source__mdt events = source('Events', 'Event', 'StartDateTime', null);
    events.Parent_Field__c = null;
    events.Junction_Object__c = 'EventRelation';
    events.Junction_Parent_Field__c = 'RelationId';
    events.Junction_Record_Field__c = 'EventId';
    events.Title__c = '{Subject}';
    events.Event_Type__c = 'meeting';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ events };

    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(customer);
    Assert.areEqual(1, countOf(result, 'meeting'), String.join(result.warnings, ' | '));
    Assert.areEqual('Menu tasting', result.events[0].title);
  }

  @IsTest
  static void anAccountPageHasItsOwnSources() {
    Account acme = new Account(Name = 'Acme');
    insert acme;
    insert new Case(AccountId = acme.Id, Subject = 'Login trouble');
    Time_Shift_Source__mdt cases = source('Account_Cases', 'Case', 'CreatedDate', 'AccountId');
    cases.Parent_Object__c = 'Account';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ cases };

    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(acme.Id);
    Assert.areEqual(1, result.events.size(), String.join(result.warnings, ' | '));
    Assert.areEqual('case', result.events[0].type);
    // A business account isn't a person account (nor is any account where
    // person accounts are off).
    Assert.isNull(TimeShiftController.personContactOf(acme.Id));
    Assert.isNull(TimeShiftController.personContactOf(contactId()));
  }

  @IsTest
  static void aPersonAccountsContactLinksMatchItsOwnContact() {
    Id account = '001000000000001AAA';
    Id person = '003000000000001AAA';
    TimeShiftContext context = new TimeShiftContext(account, 'PersonAccount', null, null, null, null);
    context.personContactId = person;
    Assert.areEqual(person, context.parentIdFor(Case.ContactId.getDescribe()), 'a Contact lookup');
    Assert.areEqual(person, context.parentIdFor(Task.WhoId.getDescribe()), 'a Name lookup, Contact or Lead');
    Assert.areEqual(account, context.parentIdFor(Case.AccountId.getDescribe()), 'an Account lookup');
    Assert.areEqual(person, context.contactId());
  }

  @IsTest
  static void aClickAndItsDetailsCanPointAtARelatedRecord() {
    Time_Shift_Source__mdt s = source('Members', 'CampaignMember', 'CreatedDate', 'ContactId');
    s.Use_Compact_Layout__c = true;
    s.Record_Id_Field__c = 'CampaignId';
    s.Details_Record_Field__c = 'CampaignId';
    s.Details_Object__c = 'Campaign';
    Id member = '00v000000000001AAA';
    Id campaign = '701000000000001AAA';
    List<TimeShiftRow> rows = new List<TimeShiftRow>{
      new TimeShiftRow(
        new Map<String, Object>{ 'Id' => member, 'CampaignId' => campaign, 'CreatedDate' => Datetime.now() }
      )
    };

    TimeShiftController.EngagementEvent e = TimeShiftPlotter.plot(
      new TimeShiftContext(null, 'Contact', null, s, null, null),
      rows
    )[0];
    Assert.areEqual(campaign, e.recordId, 'a click opens the Campaign');
    Assert.areEqual(campaign, e.detailRecordId, 'and opening shows the Campaign');
    Assert.areEqual('Campaign', e.detailObject, 'with the Campaign compact layout');
    Assert.isTrue(e.useCompactLayout);

    // Left blank, both are the item's own record, on its own object.
    s.Record_Id_Field__c = null;
    s.Details_Record_Field__c = null;
    s.Details_Object__c = null;
    e = TimeShiftPlotter.plot(new TimeShiftContext(null, 'Contact', null, s, null, null), rows)[0];
    Assert.areEqual(member, e.recordId);
    Assert.areEqual(member, e.detailRecordId);
    Assert.areEqual('CampaignMember', e.detailObject);
  }

  @IsTest
  static void salesforceDetailFieldsReplaceTheCompactLayout() {
    Time_Shift_Source__mdt cases = source('Cases', 'Case', 'CreatedDate', 'ContactId');
    cases.Use_Compact_Layout__c = true;
    TimeShiftConfig.testDetailFields = new Map<String, List<Time_Shift_Detail_Field__mdt>>{
      'Cases' => new List<Time_Shift_Detail_Field__mdt>{
        new Time_Shift_Detail_Field__mdt(Field__c = 'Status'),
        new Time_Shift_Detail_Field__mdt(Label = 'Account', Field__c = 'Account.Name')
      }
    };
    List<TimeShiftController.EngagementEvent> events = TimeShiftPlotter.run(
      new TimeShiftSoqlProvider(),
      new TimeShiftContext(contactId(), 'Contact', Datetime.now().addDays(-1), cases, null, null)
    );
    Assert.areEqual(1, events.size());
    Assert.isFalse(events[0].useCompactLayout);
    Assert.areEqual('Status', events[0].details[0].label, 'blank labels use the field label');
    Assert.areEqual('New', events[0].details[0].value);
    Assert.areEqual('Salesforce · Case', events[0].sourceLabel);
  }

  @IsTest
  static void detailFieldsWithNoLabelOfTheirOwnUseTheFieldsOwnLabel() {
    Time_Shift_Source__mdt tasks = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    TimeShiftConfig.testDetailFields = new Map<String, List<Time_Shift_Detail_Field__mdt>>{
      'Tasks' => new List<Time_Shift_Detail_Field__mdt>{
        // Setup saves "no label of its own" as Label = the field.
        new Time_Shift_Detail_Field__mdt(Label = 'Description', Field__c = 'Description'),
        new Time_Shift_Detail_Field__mdt(Label = 'Who.Name', Field__c = 'Who.Name'),
        new Time_Shift_Detail_Field__mdt(Label = 'Status', Field__c = 'Status'),
        new Time_Shift_Detail_Field__mdt(Label = 'Notes', Field__c = 'Priority')
      }
    };
    List<TimeShiftController.EngagementEvent> events = TimeShiftPlotter.run(
      new TimeShiftSoqlProvider(),
      new TimeShiftContext(contactId(), 'Contact', Datetime.now().addDays(-30), tasks, null, null)
    );
    TimeShiftController.EngagementEvent padThai;
    for (TimeShiftController.EngagementEvent e : events) {
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
      new Task(WhoId = customer, Subject = 'Urgent', Status = 'Open', Priority = 'High', ActivityDate = Date.today().addDays(-1)),
      new Task(WhoId = customer, Subject = 'Routine', Status = 'Open', Priority = 'Normal', ActivityDate = Date.today().addDays(-1))
    };
    Time_Shift_Source__mdt tasks = source('Tasks', 'Task', 'ActivityDate', 'WhoId');
    tasks.Title__c = '{Subject}';
    TimeShiftConfig.testHighlights = new Map<String, List<Time_Shift_Highlight__mdt>>{
      'Tasks' => new List<Time_Shift_Highlight__mdt>{
        // A text field is no checkbox: left out. One highlight a source: the second is too.
        new Time_Shift_Highlight__mdt(Field__c = 'Subject', Icon__c = 'dot'),
        new Time_Shift_Highlight__mdt(Field__c = 'IsHighPriority', Icon__c = 'utility:priority', Colour__c = '#C23934'),
        new Time_Shift_Highlight__mdt(Field__c = 'IsClosed', Icon__c = 'dot', Colour__c = '#2E844A')
      }
    };
    List<TimeShiftController.EngagementEvent> events = TimeShiftPlotter.run(
      new TimeShiftSoqlProvider(),
      new TimeShiftContext(customer, 'Contact', Datetime.now().addDays(-30), tasks, null, null)
    );
    TimeShiftController.EngagementEvent urgent;
    TimeShiftController.EngagementEvent routine;
    for (TimeShiftController.EngagementEvent e : events) {
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
    List<TimeShiftController.EngagementEvent> events = new List<TimeShiftController.EngagementEvent>();
    Datetime at = Datetime.newInstance(2026, 3, 3, 10, 0, 0);
    for (Integer i = 0; i < 4; i++) {
      TimeShiftController.EngagementEvent e = new TimeShiftController.EngagementEvent('t' + i, 'task', 'Sales', 'Task ' + i, null, at.addMinutes(i));
      e.dayKey = '2026-03-03';
      events.add(e);
    }
    TimeShiftController.EngagementEvent opp = new TimeShiftController.EngagementEvent('o1', 'opportunity', 'Sales', 'Opp', null, at);
    opp.dayKey = '2026-03-03';
    events.add(opp);
    List<TimeShiftController.EngagementEvent> out = TimeShiftController.groupBusyDays(events, 3);
    Integer groups = 0;
    Boolean oppItself = false;
    for (TimeShiftController.EngagementEvent e : out) {
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
    TimeShiftController.EngagementEvent withRecord = new TimeShiftController.EngagementEvent(
        'a',
        'task',
        'Sales',
        'Call back',
        null,
        Datetime.now()
      )
      .record(task.Id);
    TimeShiftController.EngagementEvent noRecord = new TimeShiftController.EngagementEvent(
      'b',
      'email',
      'Marketing',
      'Opened',
      null,
      Datetime.now()
    );
    Integer before = Limits.getQueries();
    TimeShiftController.markRights(new List<TimeShiftController.EngagementEvent>{ withRecord, noRecord });
    Assert.areEqual(before, Limits.getQueries(), 'drawing the days asks nothing about the records');
    Assert.isTrue(withRecord.canEdit, 'the object allows edit');
    Assert.isTrue(withRecord.canDelete, 'the object allows delete');
    Assert.areEqual('Task', withRecord.objectLabel);
    Assert.isFalse(noRecord.canEdit, 'no record, no menu');
    Assert.isFalse(noRecord.canDelete);

    // What the record itself allows is asked for when its menu opens.
    TimeShiftController.RecordRights rights = TimeShiftController.getRights(task.Id);
    Assert.isTrue(rights.canEdit, 'the owner can edit');
    Assert.isTrue(rights.canDelete, 'the owner can delete');
    Assert.isFalse(TimeShiftController.getRights(null).canEdit);
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source('Tasks', 'Task', 'ActivityDate', 'WhoId') };
    String todayKey = String.valueOf(today);
    String oldest = String.valueOf(today.addDays(-40));

    // Opening on today, newest first: today heads the page; the days under it
    // follow (up to a page), and every item comes with its summary.
    TimeShiftController.TimelineLoad load = TimeShiftController.getTimeline(
      customer, null, null, '0.5', null, 'Today', true, false, 7
    );
    Assert.areEqual(3, load.summary.total);
    Assert.areEqual(new List<String>{ todayKey, String.valueOf(today.addDays(-3)), oldest }, load.keys);
    Assert.areEqual(3, load.events.size());
    for (TimeShiftController.EngagementEvent e : load.events) {
      Assert.isTrue(new Set<String>(load.keys).contains(e.dayKey), 'every item belongs to a period it names');
    }

    // The same items as asking for those days separately.
    List<TimeShiftController.EngagementEvent> separately = TimeShiftController.getDays(
      customer, null, null, '0.5', null, load.keys, new List<String>()
    );
    Assert.areEqual(separately.size(), load.events.size());

    // Opening on the earliest item: that period comes first among the keys.
    load = TimeShiftController.getTimeline(customer, null, null, '0.5', null, 'Earliest item', true, false, 1);
    Assert.areEqual(new List<String>{ oldest }, load.keys);
    Assert.areEqual(1, load.events.size());

    // Across (oldest first), centred on today: the periods either side of it.
    load = TimeShiftController.getTimeline(customer, null, null, '0.5', null, 'Today', false, true, 3);
    Assert.isTrue(load.keys.contains(todayKey));
    Assert.isTrue(load.events.size() > 0);

    // A summary that used up much of the request leaves the days to a request of their own.
    TimeShiftController.testBudgetSpent = true;
    load = TimeShiftController.getTimeline(customer, null, null, '0.5', null, 'Today', true, false, 7);
    Assert.areEqual(3, load.summary.total);
    Assert.isTrue(load.keys.isEmpty());
    Assert.isTrue(load.events.isEmpty());
    TimeShiftController.testBudgetSpent = null;

    // A count of none: the summary alone.
    load = TimeShiftController.getTimeline(customer, null, null, '0.5', null, 'Today', true, false, 0);
    Assert.areEqual(3, load.summary.total);
    Assert.isTrue(load.events.isEmpty());

    // No page asked for, no rows read: just what getSummary answers.
    TimeShiftController.TimelineLoad none = TimeShiftController.getTimeline(
      null, null, null, '0.5', null, 'Today', true, false, 7
    );
    Assert.isTrue(none.keys.isEmpty());
    Assert.isTrue(none.events.isEmpty());
  }

  @IsTest
  static void anActivitySharedWithAnAccountsContactRollsUpToTheAccount() {
    if (TimeShiftConfig.sObjectType('TaskRelation') == null) {
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
    SObject relation = TimeShiftConfig.sObjectType('TaskRelation').newSObject();
    relation.put('TaskId', shared.Id);
    relation.put('RelationId', mineContact.Id);
    relation.put('IsWhat', false);
    insert relation;

    Time_Shift_Source__mdt primary = source('Primary', 'Task', 'ActivityDate', 'AccountId');
    primary.Parent_Object__c = 'Account';
    primary.Title__c = '{Subject}';
    Time_Shift_Source__mdt sharedSource = source('Shared', 'Task', 'ActivityDate', null);
    sharedSource.Parent_Object__c = 'Account';
    sharedSource.Title__c = '{Subject}';
    sharedSource.Junction_Object__c = 'TaskRelation';
    sharedSource.Junction_Parent_Field__c = 'AccountId';
    sharedSource.Junction_Record_Field__c = 'TaskId';
    sharedSource.Filter__c = 'AccountId != :parentId';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ primary, sharedSource };

    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(mine.Id, null, null, '0.5', null);
    Assert.areEqual(2, summary.total, 'on the account, and shared with it: once each');
    List<TimeShiftController.EngagementEvent> events = TimeShiftController.getDays(
      mine.Id, null, null, '0.5', null, new List<String>{ String.valueOf(day) }, new List<String>()
    );
    Set<String> titles = new Set<String>();
    for (TimeShiftController.EngagementEvent e : events) {
      titles.add(e.title);
    }
    Assert.areEqual(new Set<String>{ 'On mine', 'Shared' }, titles);
  }

  @IsTest
  static void badSourceRecordsWarnInsteadOfFailing() {
    Id customer = contactId();
    List<String> warnings = new List<String>();
    TimeShiftSoqlProvider provider = new TimeShiftSoqlProvider();
    List<Time_Shift_Source__mdt> broken = new List<Time_Shift_Source__mdt>{
      source('No_Object', 'Nope__c', 'CreatedDate', 'ContactId'),
      source('No_Field', 'Case', 'Nope__c', 'ContactId'),
      source('No_Link', 'Case', 'CreatedDate', null),
      source('Bad_Filter', 'Case', 'CreatedDate', 'ContactId')
    };
    broken[3].Filter__c = 'Nope__c = 1';
    List<TimeShiftController.Problem> problems = new List<TimeShiftController.Problem>();
    for (Time_Shift_Source__mdt s : broken) {
      TimeShiftContext context = new TimeShiftContext(
        customer,
        'Contact',
        Datetime.now().addDays(-30),
        s,
        null,
        warnings
      );
      context.problems = problems;
      List<TimeShiftController.EngagementEvent> events = TimeShiftPlotter.run(provider, context);
      Assert.isTrue(events.isEmpty());
    }
    // Records checked before querying get a configuration warning (a
    // missing object, field or link); a query that still fails (the bad
    // filter) is a problem, named with the kind of failure only.
    Assert.areEqual(3, warnings.size(), String.join(warnings, ' | '));
    Assert.areEqual(1, problems.size());
    Assert.areEqual('Bad_Filter', problems[0].source);
    for (TimeShiftController.Problem p : problems) {
      Assert.isFalse(p.source.contains('Nope__c'), 'no query text: ' + p.source);
    }

    Time_Shift_Source__mdt notAProvider = source('Not_A_Provider', 'Case', 'CreatedDate', 'ContactId');
    notAProvider.Provider_Class__c = 'TimeShiftConfig';
    Assert.isNull(TimeShiftConfig.providerFor(notAProvider, warnings));
    Time_Shift_Source__mdt apexWithoutClass = source('No_Class', 'Case', 'CreatedDate', 'ContactId');
    apexWithoutClass.Kind__c = 'Apex';
    Assert.isNull(TimeShiftConfig.providerFor(apexWithoutClass, warnings));
    Assert.areEqual(5, warnings.size());
  }

  @IsTest
  static void failuresReachTheClientAsAKindOnly() {
    QueryException missing = new QueryException();
    missing.setMessage('No such column \'Secret__c\' on entity \'Invoice__c\'');
    AuraHandledException failure = TimeShiftController.safeFailure(missing);
    Assert.areEqual('timeshift:access', failure.getMessage(), 'no query text or stack trace');

    Exception other = new DmlException();
    other.setMessage('Something odd');
    Assert.areEqual('unknown', TimeShiftController.kindOf(other));
    other.setMessage('Apex CPU time limit exceeded');
    Assert.areEqual('busy', TimeShiftController.kindOf(other));
  }

  @IsTest
  static void activeSourcesRunInSequence() {
    Time_Shift_Source__mdt later = source('Later', 'Case', 'CreatedDate', 'ContactId');
    later.Sequence__c = 20;
    Time_Shift_Source__mdt sooner = source('Sooner', 'Case', 'CreatedDate', 'ContactId');
    sooner.Sequence__c = 10;
    // A Data 360 source runs like any other.
    Time_Shift_Source__mdt dmo = source('Reservations', 'Reservation__dlm', 'Check_in_Date__c', 'Contact_ID__c');
    dmo.Kind__c = 'Data 360';
    dmo.Sequence__c = 15;
    Time_Shift_Source__mdt inactive = source('Inactive', 'Case', 'CreatedDate', 'ContactId');
    inactive.Active__c = false;
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ later, dmo, inactive, sooner };

    List<String> names = new List<String>();
    for (Time_Shift_Source__mdt s : TimeShiftConfig.sources('Contact')) {
      names.add(s.DeveloperName);
    }
    Assert.areEqual(new List<String>{ 'Sooner', 'Reservations', 'Later' }, names);
    Assert.isTrue(TimeShiftConfig.sources('Account').isEmpty());
  }

  @IsTest
  static void configuredStylingReachesTheEvents() {
    TimeShiftController.TimelineResult result = TimeShiftController.getEvents(
      contactId()
    );
    Boolean sawCase = false;
    for (TimeShiftController.EngagementEvent e : result.events) {
      if (e.type == 'case') {
        sawCase = true;
        Assert.areEqual('utility:case', e.icon);
        Assert.areEqual('#1F7A8C', e.iconColour);
        Assert.areEqual('Case updates', e.typeLabel);
        Assert.isTrue(e.useCompactLayout, 'Salesforce records expand with their compact layout');
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
    Time_Shift_Source__mdt taskSource = source('CaseTasks', 'Task', 'CreatedDate', 'WhoId');
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId'),
      taskSource
    };

    Set<String> seen = new Set<String>();
    Datetime previous;
    String cursor;
    Integer pages = 0;
    TimeShiftController.GroupPage page;
    do {
      page = TimeShiftController.getGroupPage(
        fresh.Id,
        'case',
        base.addHours(-1),
        base.addHours(1),
        3,
        cursor,
        null
      );
      if (pages == 0) {
        Assert.areEqual('View all', page.recordName);
        Assert.isFalse(page.dateOnly);
      }
      Assert.isTrue(page.items.size() <= 3);
      for (TimeShiftController.EngagementEvent e : page.items) {
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('DatedTasks', 'Task', 'ActivityDate', 'WhoId')
    };
    Datetime midday = Datetime.newInstance(Date.today(), Time.newInstance(12, 0, 0, 0));
    TimeShiftController.GroupPage page = TimeShiftController.getGroupPage(
      fresh.Id,
      'case',
      midday,
      midday,
      50,
      null,
      null
    );
    Assert.areEqual(5, page.items.size());
    Assert.isTrue(page.dateOnly);
    Assert.isFalse(page.more);
  }

  @IsTest
  static void viewAllReadsTheColumnsAskedFor() {
    // The compact layout's fields: a lookup comes back as its record's
    // name; a field the object hasn't got is left out.
    Contact fresh = new Contact(LastName = 'Columns');
    insert fresh;
    Case broken = new Case(ContactId = fresh.Id, Subject = 'Broken', Status = 'New', Origin = 'Web');
    insert broken;
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    TimeShiftController.GroupPage page = TimeShiftController.getGroupPage(
      fresh.Id,
      'case',
      Datetime.now().addHours(-1),
      Datetime.now().addHours(1),
      50,
      null,
      new List<String>{ 'Subject', 'Status', 'ContactId', 'Nope__c', 'Status' }
    );
    Assert.areEqual(1, page.items.size());
    Map<String, String> columns = page.items[0].columns;
    Assert.areEqual('Broken', columns.get('Subject'));
    Assert.areEqual('New', columns.get('Status'));
    Assert.areEqual('Columns', columns.get('ContactId'), 'the contact by name, not Id');
    Assert.isFalse(columns.containsKey('Nope__c'));
    Assert.areEqual(3, columns.size());
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
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{
      source('Cases', 'Case', 'CreatedDate', 'ContactId')
    };
    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
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
    Time_Shift_Source__mdt d360 = data360Sources()[0];
    d360.Event_Type__c = 'case';
    d360.Parent_Object__c = 'Contact';
    d360.Active__c = true;
    TimeShiftConfig.testSources.add(d360);
    page = TimeShiftController.getDays(
      fresh.Id,
      null,
      null,
      null,
      null,
      new List<String>{ day },
      new List<String>{ day }
    );
    for (TimeShiftController.EngagementEvent e : page) {
      if (e.grouped) {
        Assert.isFalse(e.pageable);
      }
    }
  }

  private static List<Time_Shift_Source__mdt> data360Sources() {
    List<Time_Shift_Source__mdt> sources = new List<Time_Shift_Source__mdt>();
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
        new Time_Shift_Source__mdt(
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
    TimeShiftConfig.PathField close = TimeShiftConfig.pathField('OpportunityContactRole', 'Opportunity.CloseDate');
    Assert.isNotNull(close, 'a lookup is followed');
    Assert.areEqual('Opportunity', close.owner);
    Assert.areEqual('Opportunity.', close.prefix);
    Assert.areEqual(Schema.DisplayType.DATE, close.field.getType());
    Assert.areEqual(
      Schema.DisplayType.DATE,
      TimeShiftConfig.fieldDescribe('OpportunityContactRole', 'Opportunity.CloseDate').getType(),
      'fieldDescribe takes a path too'
    );

    TimeShiftConfig.PathField own = TimeShiftConfig.pathField('Task', 'ActivityDate');
    Assert.areEqual('Task', own.owner);
    Assert.areEqual('', own.prefix, 'a field of the object itself');

    Assert.isNull(TimeShiftConfig.pathField('Task', 'Who.Name'), 'a polymorphic lookup is not followed');
    Assert.isNull(TimeShiftConfig.pathField('OpportunityContactRole', 'Opportunity.NoSuchField'));
    Assert.isNull(TimeShiftConfig.pathField('OpportunityContactRole', 'NoSuchLookup.CloseDate'));
    Assert.isNull(TimeShiftConfig.pathField('NoSuchObject', 'Opportunity.CloseDate'));
    Assert.isNull(TimeShiftConfig.fieldDescribe('OpportunityContactRole', 'Opportunity.NoSuchField'));
  }

  @IsTest
  static void aSourceCanBeAJunctionWithItsFieldsReachedThroughIt() {
    // OpportunityContactRole is the source (linked by ContactId); the date,
    // title and filter are the Opportunity's, by path.
    Time_Shift_Source__mdt source = source('Roles', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    source.Title__c = '{Opportunity.Name}';
    source.Filter__c = 'Opportunity.IsWon = true';
    source.Record_Id_Field__c = 'OpportunityId';
    source.Details_Record_Field__c = 'OpportunityId';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source };

    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(contactId(), null, null, '1', null);
    Assert.areEqual(1, summary.total, 'only the won opportunity is counted, by its close date');
    Assert.areEqual(1, summary.days.size());
    Assert.areEqual(String.valueOf(Date.today().addDays(-5)), summary.days[0].key);

    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
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
    Time_Shift_Source__mdt source = source('Shared', 'TaskRelation', 'Task.ActivityDate', 'RelationId');
    source.Title__c = '{Task.Subject}';
    source.Record_Id_Field__c = 'TaskId';
    source.Details_Record_Field__c = 'TaskId';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source };

    TimeShiftController.TimelineSummary summary = TimeShiftController.getSummary(fresh.Id, null, null, '1', null);
    Assert.areEqual(1, summary.total, 'counted without the deleted task');
    List<TimeShiftController.EngagementEvent> page = TimeShiftController.getDays(
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
    TimeShiftRow row = new TimeShiftRow(new Task(Subject = 'Call', Status = 'Completed'));
    Assert.areEqual('Related To', row.labelOf('WhatId'), 'a lookup reads as the page names it');
    Assert.areEqual('Related To', row.labelOf('What.Name'), 'so does a path through it that ends at Name');
    Assert.areEqual('Subject', row.labelOf('Subject'), 'other fields are as they were');
    Assert.areEqual('Status', row.labelOf('Status'));
    // Only a lookup's: the record's own Id is not one, and keeps its "ID".
    Schema.DescribeFieldResult id = Task.SObjectType.getDescribe().fields.getMap().get('id').getDescribe();
    Assert.areEqual(id.getLabel(), TimeShiftRow.plainLabel(id));
  }

  @IsTest
  static void theLegendNameCanBeAnotherObjectsPluralName() {
    Time_Shift_Source__mdt s = source('Roles', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    s.Event_Label__c = '$Object.Opportunity';
    Assert.areEqual(Opportunity.SObjectType.getDescribe().getLabelPlural(), TimeShiftConfig.legendLabel(s));
    s = source('Roles2', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    s.Event_Label__c = '$Object.NoSuchObject';
    Assert.areEqual('Roles2', TimeShiftConfig.legendLabel(s), 'an object that is not there falls back to the source\'s name');
    s = source('Roles3', 'OpportunityContactRole', 'Opportunity.CloseDate', 'ContactId');
    Assert.areEqual(
      Opportunity.SObjectType.getDescribe().getLabelPlural(),
      TimeShiftConfig.legendLabel(s),
      'with no name set, a source dated by its record is named after it'
    );
  }

  @IsTest
  static void filtersAreRewrittenToReachTheirFieldsAcrossARelationship() {
    String t = 'Task';
    Assert.areEqual(
      'Task.TaskSubtype = \'Call\'',
      TimeShiftSoqlProvider.prefixed('TaskSubtype = \'Call\'', t, 'Task.')
    );
    Assert.areEqual(
      '(Task.TaskSubtype = null OR Task.TaskSubtype NOT IN (\'Call\', \'Email\'))',
      TimeShiftSoqlProvider.prefixed('(TaskSubtype = null OR TaskSubtype NOT IN (\'Call\', \'Email\'))', t, 'Task.')
    );
    Assert.areEqual(
      'Task.Status = \'Subject = x\' AND Task.Priority = :priority',
      TimeShiftSoqlProvider.prefixed('Status = \'Subject = x\' AND Priority = :priority', t, 'Task.'),
      'text in quotes and binds are left alone'
    );
    Assert.areEqual(
      'Task.ActivityDate >= LAST_N_DAYS:30 AND Task.ActivityDate < TODAY AND Task.CreatedDate > 2026-01-31T10:00:00Z',
      TimeShiftSoqlProvider.prefixed('ActivityDate >= LAST_N_DAYS:30 AND ActivityDate < TODAY AND CreatedDate > 2026-01-31T10:00:00Z', t, 'Task.'),
      'date literals are left alone'
    );
    Assert.areEqual(
      'DAY_ONLY(Task.CreatedDate) = TODAY',
      TimeShiftSoqlProvider.prefixed('DAY_ONLY(CreatedDate) = TODAY', t, 'Task.'),
      'a function stays, its field is prefixed'
    );
    Assert.areEqual(
      'Task.CreatedBy.Name = \'A\'',
      TimeShiftSoqlProvider.prefixed('CreatedBy.Name = \'A\'', t, 'Task.'),
      'a path is prefixed whole'
    );
    Assert.isNull(TimeShiftSoqlProvider.prefixed('Id IN (SELECT TaskId FROM TaskRelation)', t, 'Task.'), 'a subquery is not rewritten');
    Assert.isNull(TimeShiftSoqlProvider.prefixed('NoSuchField__c = 1', t, 'Task.'), 'an unknown word is not guessed at');
    Assert.isNull(TimeShiftSoqlProvider.prefixed('Subject = \'open', t, 'Task.'), 'an unclosed quote is not rewritten');
  }

  @IsTest
  static void aJunctionSourceCountsThroughTheJunctionAndGivesTheSameAnswer() {
    // OpportunityContactRole links Opportunities to the Contact, as Setup
    // saves it: the Opportunity is the source, the role the junction.
    Contact c = [SELECT Id FROM Contact LIMIT 1];
    Time_Shift_Source__mdt source = source('Opps', 'Opportunity', 'CloseDate', null);
    source.Parent_Field__c = null;
    source.Junction_Object__c = 'OpportunityContactRole';
    source.Junction_Parent_Field__c = 'ContactId';
    source.Junction_Record_Field__c = 'OpportunityId';
    source.Title__c = '{Name}';
    source.Filter__c = 'IsWon = true';
    TimeShiftConfig.testSources = new List<Time_Shift_Source__mdt>{ source };

    TimeShiftDiagnostics.begin();
    Datetime since = Datetime.now().addYears(-1);
    TimeShiftContext context = new TimeShiftContext(c.Id, null, since, source, null, null);
    TimeShiftSoqlProvider provider = new TimeShiftSoqlProvider();
    List<TimeShiftContext.DayCount> counts = provider.countDays(context, TimeShiftContext.UNIT_DAY);
    Integer total = 0;
    for (TimeShiftContext.DayCount d : counts) {
      total += d.count;
    }
    Assert.areEqual(1, total, 'the won opportunity, counted from the role');
    String counted;
    for (TimeShiftDiagnostics.Query q : TimeShiftDiagnostics.queries) {
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
    TimeShiftDiagnostics.begin();
    counts = provider.countDays(new TimeShiftContext(c.Id, null, since, source, null, null), TimeShiftContext.UNIT_DAY);
    for (TimeShiftDiagnostics.Query q : TimeShiftDiagnostics.queries) {
      if (q.kind == 'count') {
        counted = q.soql;
      }
    }
    Assert.isTrue(counted.contains('FROM Opportunity '), 'a subquery in the filter keeps the original form: ' + counted);
  }

  private static Time_Shift_Source__mdt source(
    String name,
    String objectName,
    String dateField,
    String parentField
  ) {
    return new Time_Shift_Source__mdt(
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
