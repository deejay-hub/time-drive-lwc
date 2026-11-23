/**
 * The memo sources as Time Drive calls them: rows for the contact's window,
 * counts for its summary, nothing off a Contact page.
 */
@IsTest
private class MemoSourcesTest {
  @TestSetup
  static void makeData() {
    Contact c = new Contact(LastName = 'Memo Test');
    insert c;
    Memo__c m = new Memo__c(Name = 'Kick-off', Contact__c = c.Id, Memo_Date__c = Date.today().addDays(-3));
    Memo__c old = new Memo__c(Name = 'Last year', Contact__c = c.Id, Memo_Date__c = Date.today().addYears(-3));
    insert new List<Memo__c>{ m, old };
    insert new List<Memo_Item__c>{
      new Memo_Item__c(
        Memo__c = m.Id,
        Description__c = 'Agree scope',
        Status__c = 'Done',
        Occurred_At__c = Datetime.now().addDays(-3)
      ),
      new Memo_Item__c(
        Memo__c = m.Id,
        Description__c = 'Send plan',
        Status__c = 'Open',
        Flagged__c = true,
        Occurred_At__c = Datetime.now().addDays(-1)
      ),
      new Memo_Item__c(
        Memo__c = old.Id,
        Description__c = 'Ancient',
        Status__c = 'Done',
        Occurred_At__c = Datetime.now().addYears(-3)
      )
    };
  }

  private static drvrckt.TimeDriveContext lastMonth(Id recordId) {
    return new drvrckt.TimeDriveContext(recordId, Datetime.now().addDays(-30), Datetime.now().addDays(1));
  }

  @IsTest
  static void memosInTheWindowAreRowsAndCounted() {
    Id contactId = [SELECT Id FROM Contact LIMIT 1].Id;
    List<drvrckt.TimeDriveRow> rows = new MemoSource().rows(lastMonth(contactId));
    Assert.areEqual(1, rows.size(), 'only the memo in the window');
    Assert.areEqual(1, new MemoSource().counts(lastMonth(contactId), drvrckt.TimeDriveContext.UNIT_DAY).size());
  }

  @IsTest
  static void itemsAcrossEveryMemoOfTheContact() {
    Id contactId = [SELECT Id FROM Contact LIMIT 1].Id;
    List<drvrckt.TimeDriveRow> rows = new MemoItemSource().rows(lastMonth(contactId));
    Assert.areEqual(2, rows.size(), 'both recent items, from any memo; not the old one');
    Assert.areEqual(
      2,
      new MemoItemSource().counts(lastMonth(contactId), drvrckt.TimeDriveContext.UNIT_DAY).size(),
      'two days'
    );
  }

  @IsTest
  static void nothingOffAContactPage() {
    Account a = new Account(Name = 'Not a contact');
    insert a;
    Assert.isTrue(new MemoSource().rows(lastMonth(a.Id)).isEmpty());
    Assert.isTrue(new MemoItemSource().counts(lastMonth(a.Id), drvrckt.TimeDriveContext.UNIT_DAY).isEmpty());
  }
}
