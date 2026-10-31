// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
@IsTest
private class TimeDriveOpportunityProductsTest {
  // An account with three opportunities (two this year, one long ago), and
  // another account's: each with products from the standard price book.
  // Where the org's own automation won't take them (see tryInsert), the
  // tests that read them stop: there is nothing of ours to test there.
  @TestSetup
  static void products() {
    Account mine = new Account(Name = 'Acme');
    Account theirs = new Account(Name = 'Globex');
    insert new List<Account>{ mine, theirs };
    Id book = Test.getStandardPricebookId();
    Product2 laptop = new Product2(Name = 'Laptop', ProductCode = 'LAP-1', Family = 'Hardware', IsActive = true);
    Product2 support = new Product2(Name = 'Support plan', ProductCode = 'SUP-1', Family = 'Services', IsActive = true);
    insert new List<Product2>{ laptop, support };
    PricebookEntry laptopPrice = new PricebookEntry(
      Pricebook2Id = book,
      Product2Id = laptop.Id,
      UnitPrice = 1200,
      IsActive = true
    );
    PricebookEntry supportPrice = new PricebookEntry(
      Pricebook2Id = book,
      Product2Id = support.Id,
      UnitPrice = 300,
      IsActive = true
    );
    insert new List<PricebookEntry>{ laptopPrice, supportPrice };

    Opportunity recent = opportunity('Fleet refresh', mine.Id, Date.today().addDays(-10));
    Opportunity older = opportunity('First order', mine.Id, Date.today().addMonths(-3));
    Opportunity longAgo = opportunity('Pilot', mine.Id, Date.today().addYears(-5));
    Opportunity other = opportunity('Their deal', theirs.Id, Date.today().addDays(-5));
    if (!TimeDriveTestData.tryInsert(new List<Opportunity>{ recent, older, longAgo, other })) {
      return;
    }
    TimeDriveTestData.tryInsert(
      new List<OpportunityLineItem>{
        item(recent.Id, laptopPrice, 10),
        item(recent.Id, supportPrice, 10),
        item(older.Id, laptopPrice, 2),
        item(longAgo.Id, laptopPrice, 1),
        item(other.Id, supportPrice, 4)
      }
    );
  }

  // The org took the products (see the setup).
  static Boolean made() {
    return [SELECT COUNT() FROM OpportunityLineItem] > 0;
  }

  static Opportunity opportunity(String name, Id accountId, Date closeDate) {
    return new Opportunity(
      Name = name,
      AccountId = accountId,
      StageName = 'Closed Won',
      CloseDate = closeDate,
      Pricebook2Id = Test.getStandardPricebookId()
    );
  }

  static OpportunityLineItem item(Id opportunityId, PricebookEntry price, Integer quantity) {
    return new OpportunityLineItem(
      OpportunityId = opportunityId,
      PricebookEntryId = price.Id,
      Quantity = quantity,
      UnitPrice = price.UnitPrice
    );
  }

  // The source as an admin would set it up in Time Drive Setup.
  static Time_Drive_Source__mdt source() {
    return new Time_Drive_Source__mdt(
      DeveloperName = 'Opportunity_Products',
      Label = 'Products',
      Active__c = true,
      Parent_Object__c = 'Account',
      Kind__c = 'Apex',
      Provider_Class__c = 'TimeDriveOpportunityProducts',
      Object_Name__c = 'OpportunityLineItem',
      Date_Field__c = 'Opportunity.CloseDate',
      Record_Id_Field__c = 'OpportunityId',
      Title__c = '{Product2.Name}',
      Subtitle__c = '{Opportunity.Name}',
      Event_Type__c = 'product',
      Event_Label__c = 'Products'
    );
  }

  static TimeDriveContext context(Id recordId, Datetime since) {
    return new TimeDriveContext(recordId, 'Account', since, source(), null, null);
  }

  static Id account(String name) {
    return [SELECT Id FROM Account WHERE Name = :name].Id;
  }

  @IsTest
  static void readsEveryProductOnEveryOpportunityOfTheAccount() {
    if (!made()) {
      return;
    }
    TimeDriveContext ctx = context(account('Acme'), Datetime.now().addYears(-1));

    Test.startTest();
    List<TimeDriveRow> rows = new TimeDriveOpportunityProducts().getRows(ctx);
    Test.stopTest();

    // Three products on the two opportunities in the last year: not the old pilot, not Globex's deal.
    Assert.areEqual(3, rows.size(), 'the products of the account\'s opportunities in the window');
    Set<String> opportunities = new Set<String>();
    for (TimeDriveRow row : rows) {
      opportunities.add((String) row.get('Opportunity.Name'));
    }
    Assert.areEqual(new Set<String>{ 'Fleet refresh', 'First order' }, opportunities);
    // Newest first, read across both steps: the product's name and its opportunity's.
    Assert.areEqual('Fleet refresh', rows[0].get('Opportunity.Name'));
    Assert.areEqual('First order', rows[2].get('Opportunity.Name'));
    Assert.areEqual('Laptop', rows[2].get('Product2.Name'));
    Assert.areEqual(Date.today().addMonths(-3), rows[2].get('Opportunity.CloseDate'));
  }

  @IsTest
  static void plotsEachProductOnItsOpportunitysCloseDate() {
    if (!made()) {
      return;
    }
    TimeDriveContext ctx = context(account('Acme'), Datetime.now().addYears(-1));

    Test.startTest();
    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(new TimeDriveOpportunityProducts(), ctx);
    Test.stopTest();

    Assert.areEqual(3, events.size());
    TimeDriveController.EngagementEvent first = events[2];
    Assert.areEqual('Laptop', first.title, 'the title is the product');
    Assert.areEqual('First order', first.subtitle, 'the subtitle is its opportunity');
    Assert.areEqual(Date.today().addMonths(-3), first.occurredAt.date(), 'on the opportunity\'s close date');
    Id opportunityId = [SELECT Id FROM Opportunity WHERE Name = 'First order'].Id;
    Assert.areEqual(opportunityId, first.recordId, 'a click opens the opportunity');
  }

  @IsTest
  static void fillsInWhatSetupDoesNotAskAnApexSourceFor() {
    if (!made()) {
      return;
    }
    // Saved as Setup saves an Apex source: no date, title, subtitle or click, and two details.
    Time_Drive_Source__mdt s = source();
    s.Date_Field__c = null;
    s.Title__c = null;
    s.Subtitle__c = null;
    s.Record_Id_Field__c = null;
    TimeDriveContext ctx = new TimeDriveContext(account('Acme'), 'Account', Datetime.now().addYears(-1), s, null, null);
    ctx.draftDetailFields = new List<Time_Drive_Detail_Field__mdt>{
      new Time_Drive_Detail_Field__mdt(Label = 'Quantity', Field__c = 'Quantity', Format__c = 'Number'),
      new Time_Drive_Detail_Field__mdt(Label = 'Stage', Field__c = 'Opportunity.StageName', Format__c = 'Text')
    };

    List<TimeDriveController.EngagementEvent> events = TimeDrivePlotter.run(new TimeDriveOpportunityProducts(), ctx);

    Assert.areEqual(3, events.size(), 'every product is plotted, none skipped for want of a date');
    TimeDriveController.EngagementEvent first = events[2];
    Assert.areEqual('Laptop', first.title);
    Assert.areEqual('First order', first.subtitle);
    Assert.areEqual(Date.today().addMonths(-3), first.occurredAt.date());
    // A click opens the opportunity product itself.
    Assert.areEqual(
      [SELECT Id FROM OpportunityLineItem WHERE Opportunity.Name = 'First order'].Id,
      first.recordId,
      'a click opens the opportunity product'
    );
    Assert.isTrue(ctx.warnings.isEmpty(), String.join(ctx.warnings, ' | '));
    // A source that sets its own keeps it.
    Time_Drive_Source__mdt own = source();
    own.Title__c = '{Product2.ProductCode}';
    TimeDriveContext mine = new TimeDriveContext(account('Acme'), 'Account', null, own, null, null);
    List<TimeDriveController.EngagementEvent> coded = TimeDrivePlotter.run(new TimeDriveOpportunityProducts(), mine);
    Assert.areEqual('{Product2.ProductCode}', mine.source.Title__c);
    Assert.areEqual('LAP-1', coded[coded.size() - 1].title, 'its own title, read with the rest');
  }

  @IsTest
  static void readsOnlyTheDaysAskedFor() {
    if (!made()) {
      return;
    }
    TimeDriveContext ctx = context(account('Acme'), null);
    // Just the week around the recent opportunity, as a page of quiet days asks.
    ctx.ranges = new List<TimeDriveController.TimeWindow>{
      new TimeDriveController.TimeWindow(Datetime.now().addDays(-14), Datetime.now().addDays(-7))
    };
    List<TimeDriveRow> rows = new TimeDriveOpportunityProducts().getRows(ctx);
    Assert.areEqual(2, rows.size(), 'the two products closed in that week');

    // No window at all: the whole history, the old pilot too.
    List<TimeDriveRow> all = new TimeDriveOpportunityProducts().getRows(context(account('Acme'), null));
    Assert.areEqual(4, all.size());
  }

  @IsTest
  static void keepsToMaxRecordsAndReadsTheFieldsTheSourceShows() {
    if (!made()) {
      return;
    }
    Time_Drive_Source__mdt s = source();
    s.Max_Records__c = 2;
    s.Subtitle__c = '{Product2.Family}';
    TimeDriveContext ctx = new TimeDriveContext(account('Acme'), 'Account', null, s, null, null);
    List<TimeDriveRow> rows = new TimeDriveOpportunityProducts().getRows(ctx);
    // At most Max Records, newest first: the two products of the latest opportunity.
    Assert.areEqual(2, rows.size());
    Set<Object> families = new Set<Object>{ rows[0].get('Product2.Family'), rows[1].get('Product2.Family') };
    Assert.areEqual(new Set<Object>{ 'Hardware', 'Services' }, families, 'the subtitle\'s field is read too');
  }

  @IsTest
  static void showsNothingOffAnAccountPage() {
    Contact person = new Contact(LastName = 'Park', AccountId = account('Acme'));
    insert person;
    TimeDriveContext ctx = new TimeDriveContext(person.Id, 'Contact', null, source(), null, null);
    Assert.isTrue(new TimeDriveOpportunityProducts().getRows(ctx).isEmpty(), 'products belong on the account');
  }

  @IsTest
  static void isOfferedInSetupAsAnApexSource() {
    Boolean offered = false;
    for (TimeDriveSetupController.Option o : TimeDriveSetupController.getApexProviders()) {
      offered = offered || (o.value == 'TimeDriveOpportunityProducts' && o.detail == 'Returns rows to plot');
    }
    Assert.isTrue(offered, 'Setup lists it among the Apex sources');
  }
}
