@IsTest
private class TimeDriveEmailsTest {
  // A message as the query returns it (its tracking fields can't be set).
  static EmailMessage message(Map<String, Object> fields) {
    return (EmailMessage) JSON.deserialize(JSON.serialize(fields), EmailMessage.class);
  }

  @IsTest
  static void saysWhetherAnEmailWasOpenedBouncedOrNot() {
    Assert.areEqual(
      TimeDriveEmails.BOUNCED,
      TimeDriveEmails.stateOf(message(new Map<String, Object>{ 'IsBounced' => true, 'IsOpened' => true }))
    );
    Assert.areEqual(
      TimeDriveEmails.OPENED,
      TimeDriveEmails.stateOf(message(new Map<String, Object>{ 'IsOpened' => true, 'IsTracked' => true }))
    );
    Assert.areEqual(
      TimeDriveEmails.UNOPENED,
      TimeDriveEmails.stateOf(message(new Map<String, Object>{ 'IsTracked' => true, 'Incoming' => false }))
    );
    // Received, or sent untracked: nothing to say.
    Assert.isNull(TimeDriveEmails.stateOf(message(new Map<String, Object>{ 'Incoming' => true })));
    Assert.isNull(TimeDriveEmails.stateOf(message(new Map<String, Object>{ 'IsTracked' => false })));
  }

  @IsTest
  static void namesThePrimaryRecipientAndCountsTheOthers() {
    EmailMessage m = message(
      new Map<String, Object>{ 'ToAddress' => 'sam@example.com; ada@example.com', 'CcAddress' => 'lee@example.com' }
    );
    Map<String, String> names = new Map<String, String>{ m.Id + '|sam@example.com' => 'Sam Lee' };
    Assert.areEqual('Sent to: Sam Lee and 2 others', TimeDriveEmails.sentTo(m, names));
    // A known recipient leads, wherever they are in the list.
    Assert.areEqual(
      'Sent to: Sam Lee and 1 other',
      TimeDriveEmails.sentTo(message(new Map<String, Object>{ 'ToAddress' => 'ada@example.com, sam@example.com' }), names)
    );
    Assert.areEqual(
      'Sent to: ada@example.com',
      TimeDriveEmails.sentTo(message(new Map<String, Object>{ 'ToAddress' => 'ada@example.com' }), names)
    );
    Assert.isNull(TimeDriveEmails.sentTo(message(new Map<String, Object>()), names));
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

    TimeDriveController.EngagementEvent e = new TimeDriveController.EngagementEvent(
        'e1',
        'sales_email',
        'Sales',
        'Proposal',
        'Anything the source said',
        Datetime.now()
      )
      .record(m.Id);
    TimeDriveEmails.enrich(new List<TimeDriveController.EngagementEvent>{ e });
    // The timeline's own subtitle, whatever the source's template said.
    Assert.areEqual('Sent to: Sam Lee and 1 other', e.subtitle);
  }
}
