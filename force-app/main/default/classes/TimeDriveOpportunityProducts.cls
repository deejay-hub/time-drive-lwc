/**
 * An example Apex source, for an Account page: the products on every
 * opportunity of the account (Account › Opportunity › Opportunity Product),
 * two steps from the page, further than Setup's lookups and junctions reach.
 *
 * An Apex source answers two questions. counts: how many products each
 * period has, for the timeline's summary (one grouped query, whatever the
 * history). rows: the products on the days on screen. Each row is an
 * Opportunity Product, so its fields fill the title, subtitle and the detail
 * fields chosen in Setup (Quantity, TotalPrice, Opportunity.StageName ...).
 * Setup asks an Apex source for no date, title, subtitle or click, so the
 * class says them (plotBy): each product on its opportunity's close date,
 * named for the product, under its opportunity, a click opening the product.
 *
 * To use it, add a source of kind Apex on the Account page in Time Drive
 * Setup and choose this class.
 */
public with sharing class TimeDriveOpportunityProducts extends TimeDriveApexSource {
  private static final String CLOSE_DATE = 'Opportunity.CloseDate';
  private static final String THIS_ACCOUNT = 'Opportunity.AccountId = :accountId';

  /**
   * How many of the account's opportunity products each period has.
   *
   * @param context the request context
   * @param unit the period to count by
   * @return the counts; none off an account page
   */
  public override List<TimeDriveContext.DayCount> counts(TimeDriveContext context, String unit) {
    if (context.recordId?.getSObjectType() != Account.SObjectType) {
      return new List<TimeDriveContext.DayCount>();
    }
    return context.countBy(
      OpportunityLineItem.SObjectType,
      CLOSE_DATE,
      THIS_ACCOUNT,
      new Map<String, Object>{ 'accountId' => context.recordId },
      unit
    );
  }

  /**
   * The account's opportunity products on the days asked for, newest first.
   *
   * @param context the request context
   * @return a row for each opportunity product; none off an account page
   */
  public override List<TimeDriveRow> rows(TimeDriveContext context) {
    List<TimeDriveRow> rows = new List<TimeDriveRow>();
    if (context.recordId?.getSObjectType() != Account.SObjectType) {
      return rows;
    }
    context.plotBy(CLOSE_DATE).title('{Product2.Name}').subtitle('{Opportunity.Name}').opens('Id');
    Map<String, Object> binds = new Map<String, Object>{
      'accountId' => context.recordId,
      'most' => context.maxRecords()
    };
    List<String> always = new List<String>{ 'Id', CLOSE_DATE };
    // Where the org has several currencies, each product's own, so its prices show in it.
    if (UserInfo.isMultiCurrencyOrganization()) {
      always.add('CurrencyIsoCode');
    }
    String soql =
      'SELECT ' +
      String.join(context.fieldsToQuery(OpportunityLineItem.SObjectType, always), ', ') +
      ' FROM OpportunityLineItem WHERE ' +
      THIS_ACCOUNT +
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
