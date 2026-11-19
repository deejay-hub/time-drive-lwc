/**
 * A Time Drive Apex source for Contact pages: every item on every memo of
 * the contact (Contact › Memo__c › Memo_Item__c, two steps from the page),
 * each at its Occurred At, described, under its memo and status, a click
 * opening the item. Choose details in Setup (Status__c, Flagged__c,
 * Memo__r.Name: the memo's name links to the memo).
 *
 * Add it in Time Drive Setup as a source of kind Apex on the Contact page.
 */
public with sharing class MemoItemSource extends drvrckt.TimeDriveApexSource {
  private static final String OCCURRED_AT = 'Occurred_At__c';
  // Any memo of the contact: the item's parent links to the page.
  private static final String THIS_CONTACT = 'Memo__r.Contact__c = :contactId';

  /**
   * How many items each period has, across all the contact's memos.
   *
   * @param context the request context
   * @param unit the period to count by
   * @return the counts; none off a Contact page
   */
  public override List<drvrckt.TimeDriveContext.DayCount> counts(drvrckt.TimeDriveContext context, String unit) {
    if (context.recordId?.getSObjectType() != Contact.SObjectType) {
      return new List<drvrckt.TimeDriveContext.DayCount>();
    }
    return context.countBy(
      Memo_Item__c.SObjectType,
      OCCURRED_AT,
      THIS_CONTACT,
      new Map<String, Object>{ 'contactId' => context.recordId },
      unit
    );
  }

  /**
   * The contact's memo items on the days asked for, newest first.
   *
   * @param context the request context
   * @return a row for each item; none off a Contact page
   */
  public override List<drvrckt.TimeDriveRow> rows(drvrckt.TimeDriveContext context) {
    List<drvrckt.TimeDriveRow> rows = new List<drvrckt.TimeDriveRow>();
    if (context.recordId?.getSObjectType() != Contact.SObjectType) {
      return rows;
    }
    context.plotBy(OCCURRED_AT).title('{Description__c}').subtitle('{Memo__r.Name} · {Status__c}').opens('Id');
    Map<String, Object> binds = new Map<String, Object>{
      'contactId' => context.recordId,
      'most' => context.maxRecords()
    };
    String soql =
      'SELECT ' +
      String.join(context.fieldsToQuery(new List<String>{ 'Id', OCCURRED_AT }), ', ') +
      ' FROM Memo_Item__c WHERE ' +
      THIS_CONTACT +
      context.dateCondition(Memo_Item__c.SObjectType, OCCURRED_AT, binds) +
      ' ORDER BY ' +
      OCCURRED_AT +
      ' DESC, Id DESC LIMIT :most';
    for (SObject item : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
      rows.add(new drvrckt.TimeDriveRow(item));
    }
    return rows;
  }
}
