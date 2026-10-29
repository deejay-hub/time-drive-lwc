@IsTest
private class TimeDriveDiagnosticControllerTest {
  private static Contact customer;

  private static void setUpData() {
    customer = new Contact(LastName = 'Diagnosed');
    insert customer;
    Date today = Date.today();
    List<Task> tasks = new List<Task>();
    for (Integer i = 0; i < 12; i++) {
      tasks.add(new Task(WhoId = customer.Id, Subject = 'Task ' + i, ActivityDate = today.addDays(-i), Status = 'Completed'));
    }
    insert tasks;
    Time_Drive_Source__mdt active = source('Diag_Tasks', true);
    Time_Drive_Source__mdt off = source('Diag_Off', false);
    off.Variant_Group__c = 'Contact Tasks';
    TimeDriveConfig.testSources = new List<Time_Drive_Source__mdt>{ active, off };
    TimeDriveDiagnosticController.testCanCustomize = true;
  }

  private static Time_Drive_Source__mdt source(String name, Boolean isActive) {
    return new Time_Drive_Source__mdt(
      DeveloperName = name,
      Label = name,
      Active__c = isActive,
      Sequence__c = 1,
      Parent_Object__c = 'Contact',
      Object_Name__c = 'Task',
      Date_Field__c = 'ActivityDate',
      Parent_Field__c = 'WhoId',
      Event_Type__c = 'task',
      Category__c = 'Sales',
      Title__c = '{Subject}'
    );
  }

  private static Boolean has(List<TimeDriveDiagnosticController.Fact> facts, String label) {
    for (TimeDriveDiagnosticController.Fact f : facts) {
      if (f.label.startsWith(label)) {
        return true;
      }
    }
    return false;
  }

  @IsTest
  static void theFirstLoadReportsEveryQueryItRan() {
    setUpData();
    TimeDriveDiagnosticController.Report report = TimeDriveDiagnosticController.run(customer.Id, 'load', 'Across', '0.5', null);
    Assert.areEqual('load', report.mode);
    Set<String> kinds = new Set<String>();
    for (TimeDriveDiagnostics.Query q : report.queries) {
      kinds.add(q.kind);
      Assert.isNotNull(q.soql, 'the SOQL as run');
      Assert.isNotNull(q.ms);
    }
    Assert.isTrue(kinds.contains('count'), 'the summary counted');
    Assert.isTrue(kinds.contains('rows'), 'the days were read');
    Assert.isTrue(report.totals.queries >= report.queries.size() - 1, 'the totals include what was recorded');
    Assert.areEqual(12, report.totals.days);
    Assert.isTrue(report.totals.events > 0);
    Assert.isFalse(TimeDriveDiagnostics.active, 'recording is switched off again');
    Assert.isTrue(has(report.permissions, 'Modify All Data'));
    Assert.isTrue(has(report.permissions, 'This record'));
    Assert.isTrue(has(report.page, 'Record'));
  }

  @IsTest
  static void theSourcesSayWhichWereUsedAndWhichWereIgnored() {
    setUpData();
    TimeDriveDiagnosticController.Report report = TimeDriveDiagnosticController.run(customer.Id, 'load', 'Down', '0.5', null);
    Map<String, TimeDriveDiagnosticController.SourceRow> byName = new Map<String, TimeDriveDiagnosticController.SourceRow>();
    for (TimeDriveDiagnosticController.SourceRow r : report.sources) {
      byName.put(r.developerName, r);
    }
    Assert.areEqual('used', byName.get('Diag_Tasks').status);
    Assert.isTrue(byName.get('Diag_Tasks').queries > 0, 'its queries are counted against it');
    Assert.isTrue(byName.get('Diag_Tasks').counted);
    Assert.areEqual('ignored', byName.get('Diag_Off').status);
    Assert.isTrue(byName.get('Diag_Off').reason.contains('Inactive'));
    Assert.isTrue(byName.get('Diag_Off').reason.contains('Contact Tasks'), 'a variant says so');
    Assert.isNotNull(byName.get('Diag_Tasks').access, 'what the user may do with the object');
    Assert.areEqual('used', report.sources[0].status, 'used sources come first');
  }

  @IsTest
  static void aScrollReportsWhatTheCardHandsTheServer() {
    setUpData();
    TimeDriveDiagnosticController.Report report = TimeDriveDiagnosticController.run(customer.Id, 'scroll', 'Down', '0.5', null);
    Assert.areEqual('scroll', report.mode);
    Assert.isTrue(has(report.asked, 'Days asked for'));
    Assert.isTrue(has(report.asked, 'Sources the summary found empty'));
    for (TimeDriveDiagnostics.Query q : report.queries) {
      Assert.areNotEqual('count', q.kind, 'a scroll counts nothing');
    }
    Assert.isTrue(report.totals.events > 0);
  }

  @IsTest
  static void onlyAdminsMayRun() {
    setUpData();
    TimeDriveDiagnosticController.testCanCustomize = false;
    try {
      TimeDriveDiagnosticController.run(customer.Id, 'load', 'Across', '0.5', null);
      Assert.fail('expected a refusal');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Customize Application'));
    }
    TimeDriveDiagnosticController.testCanCustomize = true;
    try {
      TimeDriveDiagnosticController.run(null, 'load', 'Across', '0.5', null);
      Assert.fail('expected a request for an Id');
    } catch (AuraHandledException e) {
      Assert.isTrue(e.getMessage().contains('Id'));
    }
  }
}
