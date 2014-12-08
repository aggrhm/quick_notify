module QuickNotify

  class Mailer < ActionMailer::Base

    def notification_email(notif)
      mail(
        to: notif.user.email,
        subject: notif.subject,
        body: notif.full_message || notif.message
      )
    end

    def app_email(opts)
      @scope = opts[:scope]
      mail(opts)
    end

  end

end
