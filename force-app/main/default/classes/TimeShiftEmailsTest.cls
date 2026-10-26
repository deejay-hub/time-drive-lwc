@IsTest
private class TimeShiftEmailsTest {
  // A message as the query returns it (its tracking fields can't be set).
  static EmailMessage message(Map<String, Object> fields) {
    return (EmailMessage) JSON.deserialize(JSON.serialize(fields), EmailMessage.class);
  }

  @IsTest
  static void saysWhetherAnEmailWasOpenedBouncedOrNot() {
    Assert.areEqual(
      TimeShiftEmails.BOUNCED,
      TimeShiftEmails.stateOf(message(new Map<String, Object>{ 'IsBounced' => true, 'IsOpened' => true }))
    );
    Assert.areEqual(
      TimeShiftEmails.OPENED,
      TimeShiftEmails.stateOf(message(new Map<String, Object>{ 'IsOpened' => true, 'IsTracked' => true }))
    );
    Assert.areEqual(
      TimeShiftEmails.UNOPENED,
      TimeShiftEmails.stateOf(message(new Map<String, Object>{ 'IsTracked' => true, 'Incoming' => false }))
    );
    // Received, or sent untracked: nothing to say.
    Assert.isNull(TimeShiftEmails.stateOf(message(new Map<String, Object>{ 'Incoming' => true })));
    Assert.isNull(TimeShiftEmails.stateOf(message(new Map<String, Object>{ 'IsTracked' => false })));
  }

  @IsTest
  static void namesThePrimaryRecipientAndCountsTheOthers() {
    EmailMessage m = message(
      new Map<String, Object>{ 'ToAddress' => 'sam@example.com; ada@example.com', 'CcAddress' => 'lee@example.com' }
    );
    Map<String, String> names = new Map<String, String>{ m.Id + '|sam@example.com' => 'Sam Lee' };
    Assert.areEqual('Sent to: Sam Lee and 2 others', TimeShiftEmails.sentTo(m, names));
    // A known recipient leads, wherever they are in the list.
    Assert.areEqual(
      'Sent to: Sam Lee and 1 other',
      TimeShiftEmails.sentTo(message(new Map<String, Object>{ 'ToAddress' => 'ada@example.com, sam@example.com' }), names)
    );
    Assert.areEqual(
      'Sent to: ada@example.com',
      TimeShiftEmails.sentTo(message(new Map<String, Object>{ 'ToAddress' => 'ada@example.com' }), names)
    );
    Assert.isNull(TimeShiftEmails.sentTo(message(new Map<String, Object>()), names));
  }

  @IsTest
  static void addsRecipientsToAnEmailMessagesSubtitle() {
    Contact sam = new Contact(LastName = 'Lee', FirstName = 'Sam', Email = 'sam@example.com');
    insert sam;
    EmailMessage m = new EmailMessage(
      Subject = 'Proposal',
      ToAddress = 'sam@example.com; ada@example.com',
      FromName = 'Ada Park',
      FromAddress = 'ada.park@example.com',
      Status = '3',
      Incoming = false,
      MessageDate = Datetime.now()
    );
    insert m;
    insert new EmailMessageRelation(EmailMessageId = m.Id, RelationId = sam.Id, RelationType = 'ToAddress', RelationAddress = 'sam@example.com');

    TimeShiftController.EngagementEvent e = new TimeShiftController.EngagementEvent(
        'e1',
        'sales_email',
        'Sales',
        'Proposal',
        'Anything the source said',
        Datetime.now()
      )
      .record(m.Id);
    TimeShiftEmails.enrich(new List<TimeShiftController.EngagementEvent>{ e });
    // The timeline's own subtitle, whatever the source's template said.
    Assert.areEqual('Sent to: Sam Lee and 1 other', e.subtitle);
  }
}
