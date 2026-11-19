/**
 * A Time Drive Apex source for Contact pages: the contact's memos (Memo__c,
 * linked by Contact__c), each on its Memo Date, named for the memo, its
 * description under it, a click opening it.
 *
 * Add it in Time Drive Setup as a source of kind Apex on the Contact page.
 */
public with sharing class MemoSource extends drvrckt.TimeDriveApexSource {
  private static final String THIS_CONTACT = 'Contact__c = :contactId';

  /**
   * How many of the contact's memos each period has: one grouped query.
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
      Memo__c.SObjectType,
      'Memo_Date__c',
      THIS_CONTACT,
      new Map<String, Object>{ 'contactId' => context.recordId },
      unit
    );
  }

  /**
   * The contact's memos on the days asked for, newest first.
   *
   * @param context the request context
   * @return a row for each memo; none off a Contact page
   */
  public override List<drvrckt.TimeDriveRow> rows(drvrckt.TimeDriveContext context) {
    List<drvrckt.TimeDriveRow> rows = new List<drvrckt.TimeDriveRow>();
    if (context.recordId?.getSObjectType() != Contact.SObjectType) {
      return rows;
    }
    context.plotBy('Memo_Date__c').title('{Name}').subtitle('{Description__c}').opens('Id');
    Map<String, Object> binds = new Map<String, Object>{
      'contactId' => context.recordId,
      'most' => context.maxRecords()
    };
    String soql =
      'SELECT ' +
      String.join(context.fieldsToQuery(new List<String>{ 'Id', 'Memo_Date__c' }), ', ') +
      ' FROM Memo__c WHERE ' +
      THIS_CONTACT +
      context.dateCondition(Memo__c.SObjectType, 'Memo_Date__c', binds) +
      ' ORDER BY Memo_Date__c DESC, Id DESC LIMIT :most';
    for (SObject memo : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
      rows.add(new drvrckt.TimeDriveRow(memo));
    }
    return rows;
  }
}
