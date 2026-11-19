// Run as the running user on purpose; tests where what a person may do is the point run as a user with
// only the permission set (see the Preference and Progress tests).
@SuppressWarnings('PMD.ApexUnitTestClassShouldHaveRunAs')
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
    // Names are kept by message and address, so the message has an Id of its own.
    Id messageId = Id.valueOf(EmailMessage.SObjectType.getDescribe().getKeyPrefix() + '0'.repeat(11) + '1');
    EmailMessage m = message(
      new Map<String, Object>{
        'Id' => messageId,
        'ToAddress' => 'sam@example.com; ada@example.com',
        'CcAddress' => 'lee@example.com'
      }
    );
    Map<String, String> names = new Map<String, String>{ messageId + '|sam@example.com' => 'Sam Lee' };
    Assert.areEqual(
      String.format(Label.Time_Drive_Server_Sent_To_Others, new List<String>{ 'Sam Lee', '2' }),
      TimeDriveEmails.sentTo(m, names)
    );
    // A known recipient leads, wherever they are in the list.
    Assert.areEqual(
      String.format(Label.Time_Drive_Server_Sent_To_One_Other, new List<String>{ 'Sam Lee' }),
      TimeDriveEmails.sentTo(
        message(new Map<String, Object>{ 'Id' => messageId, 'ToAddress' => 'ada@example.com, sam@example.com' }),
        names
      )
    );
    // Not known by this message: the address it went to.
    Assert.areEqual(
      String.format(Label.Time_Drive_Server_Sent_To, new List<String>{ 'sam@example.com' }),
      TimeDriveEmails.sentTo(message(new Map<String, Object>{ 'ToAddress' => 'sam@example.com' }), names)
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
    insert new EmailMessageRelation(
      EmailMessageId = m.Id,
      RelationId = sam.Id,
      RelationType = 'ToAddress',
      RelationAddress = 'sam@example.com'
    );

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
    Assert.areEqual(
      String.format(Label.Time_Drive_Server_Sent_To_One_Other, new List<String>{ 'Sam Lee' }),
      e.subtitle
    );
  }
}
