/**
 * An example Apex source, for an Account page: the products on every
 * opportunity of the account (Account › Opportunity › Opportunity Product),
 * two steps from the page, further than Setup's lookups and junctions reach.
 *
 * An Apex source returns rows and Time Drive plots them. Here each row is an
 * Opportunity Product, so its fields fill the title, subtitle and the detail
 * fields chosen in Setup (Quantity, TotalPrice, Opportunity.StageName ...).
 * Setup asks an Apex source for no date, title, subtitle or click, so the
 * class says them (plotBy): each product on its opportunity's close date,
 * named for the product, under its opportunity, a click opening the product.
 *
 * To use it, add a source of kind Apex on the Account page in Time Drive
 * Setup and choose this class.
 */
public with sharing class TimeDriveOpportunityProducts implements TimeDriveRowProvider {
  private static final String CLOSE_DATE = 'Opportunity.CloseDate';

  /**
   * The account's opportunity products on the days asked for, newest first.
   *
   * @param context the request context
   * @return a row for each opportunity product; none off an account page
   */
  public List<TimeDriveRow> getRows(TimeDriveContext context) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    if (context.recordId?.getSObjectType() != Account.SObjectType) {
      return rows;
    }
    context.plotBy(CLOSE_DATE).title('{Product2.Name}').subtitle('{Opportunity.Name}').opens('Id');
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => context.recordId,
      'most' => context.maxRecords()
    };
    String soql =
      'SELECT ' +
      String.join(context.fieldsToQuery(new List<String>{ 'Id', CLOSE_DATE }), ', ') +
      ' FROM OpportunityLineItem WHERE Opportunity.AccountId = :accountId' +
      context.dateCondition(OpportunityLineItem.SObjectType, CLOSE_DATE, binds) +
      ' ORDER BY ' +
      CLOSE_DATE +
      ' DESC, Id DESC LIMIT :most';
    for (SObject item : Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE)) {
      rows.add(new TimeDriveRow(item));
    }
    return rows;
  }
}
