module QuickNotify

  class Mailer < ActionMailer::Base

    def notification_email(notif)
      mail(
        from: QuickNotify.options[:email][:from],
        to: notif.user.email,
        subject: notif.subject,
        body: notif.full_message || notif.message
      )
    end

  end

end
